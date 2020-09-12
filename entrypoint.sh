#!/bin/bash

set -o pipefail


default_semvar_bump=${DEFAULT_BUMP:-patch}
with_v=${WITH_V:-false}
release_branch=${RELEASE_BRANCH:-master}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}

cd ${GITHUB_WORKSPACE}/${source}
current_branch=$(git rev-parse --abbrev-ref HEAD)
echo "current_branch = $current_branch"

pre_release="true"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    if [[ "${current_branch}" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

git fetch --tags

echo "$(git for-each-ref --sort=-v:refname --format '%(refname)')"
echo "$(git for-each-ref --sort=-v:refname --format '%(refname)' | cut -d / -f 3- | grep -E '^v?[0-9]+.[0-9]+.[0-9]+$*')"

# get latest tag that looks like a semver (with or without v)
case "$tag_context" in
    *repo*) tag=$(git for-each-ref --sort=-v:refname --format '%(refname)' | cut -d / -f 3- | grep -E '^v?[0-9]+.[0-9]+.[0-9]+$*' | head -n1);;
    *branch*) tag=$(git tag --list --merged HEAD --sort=-committerdate | grep -E '^v?[0-9]+.[0-9]+.[0-9]+$*' | head -n1);;
    * ) echo "Unrecognised context"; exit 1;;
esac

echo $tag

# if there are none, start tags at INITIAL_VERSION which defaults to 0.0.0
if [ -z "$tag" ]
then
    log=$(git log --pretty='%B')
    tag="$initial_version"
else
    log=$(git log $tag..HEAD --pretty='%B')
fi

echo $tag

# get current commit hash for tag
tag_commit=$(git rev-list -n 1 $tag)
# get current commit hash
commit=$(git rev-parse HEAD)
if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo ::set-output name=tag::$tag
    exit 0
fi

echo "previous_tag = $tag"

new=""
function default-bump {
  if [ "$default_semvar_bump" == "none" ]; then
    echo "Default bump was set to none. Skipping..."
    exit 0
  else
    semver bump "${default_semvar_bump}" $tag
  fi
}

function bump-level {
    case "$log" in
        *#major* ) new=$(semver bump major $tag); part="major";;
        *#minor* ) new=$(semver bump minor $tag); part="minor";;
        *#patch* ) new=$(semver bump patch $tag); part="patch";;
        * ) new=$(default-bump); part=$default_semvar_bump;;
    esac
}

if $pre_release

if [[ $tag == "v"* ]]
then
    tag=$(echo $tag | sed -e "s/^v//""")
fi

then
    if [[ $tag == *"beta"* ]]
    then
        beta_version=$(echo $tag | cut -f3 -d"-")
        tag=$(echo $tag | cut -f1 -d"-")
        new_beta_version=$((beta_version+1))
        new="${tag}-beta-${new_beta_version}"
    else
        tag=$(echo $tag | cut -f1 -d"-")
        bump-level
        new="${new}-beta-1"
    fi
else
    if [[ $tag == *"beta"* ]]
    then
        new=$(echo $tag | cut -f1 -d"-")
    else
        bump-level
    fi
fi

if [ ! -z "$new" ]
then
	if $with_v
	then
		new="v$new"
	fi
fi
echo $new

# set outputs
echo ::set-output name=new_tag::$new
echo ::set-output name=part::$part
echo ::set-output name=tag::$new

if $dryrun
then
    exit 0
fi 

# create local git tag
git tag $new

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

git_refs_response=$(
curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF
{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
)

git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

echo "::debug::${git_refs_response}"
if [ "${git_ref_posted}" = "refs/tags/${new}" ]; then
  exit 0
else
  echo "::error::Tag was not created properly."
  exit 1
fi