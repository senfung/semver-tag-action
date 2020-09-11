FROM alpine
LABEL "repository"="https://github.com/senfung/semver-tag-action"
LABEL "homepage"="https://github.com/senfung/semver-tag-action"
LABEL "maintainer"="senfung"

COPY ./semver/semver ./semver/semver
RUN install ./semver/semver /usr/local/bin
COPY entrypoint.sh /entrypoint.sh

RUN apk update && apk add bash git curl jq

ENTRYPOINT ["/entrypoint.sh"]