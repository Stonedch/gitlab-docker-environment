#!/bin/bash

set -a
source ./.env
set +a

projects=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_URL/api/v4/projects" | jq -r '.[] | "\(.path) \(.id)"')

echo "$projects" | while read name id; do
  echo "Syncing $name..."
  
  Клонировать с GitLab
  git clone --mirror "https://$GITLAB_USER:$GITLAB_TOKEN@$GITLAB_URL/$GITLAB_USER/$name.git"
  cd "$name.git"
  
  Пушить на GitHub
  git push --mirror "https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$name.git"
  
  cd ..
  rm -rf "$name.git"
  
  echo "Synced: $name"
done

