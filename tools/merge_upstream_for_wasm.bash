#!/bin/bash

set -e

if [[ "$1" == "finish" ]]; then
    echo '+ Finishing up to merge upstream'
    branch="$(git name-rev --name-only HEAD)"

    if [[ "$branch" != merge-from-*-to-* ]]; then
        echo "+ Current '$branch' is not a branch to merge upstream. Please run './build.sh merge-upstream' to prepare branch to merge upstream"
        exit 1
    fi

    echo "+ Merging '${branch}' branch into 'wasm' branch"
    git checkout wasm
    git merge --no-ff --no-edit "$branch"

    echo "+ Updating remote 'upstream' branch"
    git push --no-verify origin upstream:upstream

    echo "Successfully merged upstream into 'wasm' branch"
    exit 0
fi

prev_branch="$(git name-rev --name-only HEAD)"

function current_version_from_commits() {
    local msg line
    while IFS= read -r line; do
        # hash="${line%% *}"
        msg="${line#* }"
        if [[ "$msg" =~ ^patch\ ([[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+): ]]; then
            echo "${BASH_REMATCH[1]}"
            return
        fi
    done < <(git log --pretty='%H %s' --max-count=100)
    echo '+ Version could not be detected in commit messages' 1>&2
    git checkout "${prev_branch}" >/dev/null
    exit 1
}

git checkout upstream >/dev/null

before_ver="$(current_version_from_commits)"
before_hash="$(git rev-parse HEAD)"

echo '+ Pulling upstream...'
git pull https://github.com/vim/vim.git master >/dev/null

after_ver="$(current_version_from_commits)"
after_hash="$(git rev-parse HEAD)"

if [[ "$before_hash" == "$after_hash" ]]; then
    echo "+ No new patch was found. The latest version is still '${before_ver}' (${before_hash})" 1>&2
    git checkout "${prev_branch}" >/dev/null
    exit 1
fi

echo
echo '+ Detected new patches:'
echo "    Before version=${before_ver} (${before_hash})"
echo "    After version=${after_ver} (${after_hash})"

echo
echo "+ Merging ${before_ver}...${after_ver}"

git --no-pager log --oneline --graph "HEAD...${before_hash}"

git checkout wasm >/dev/null

echo '+ Creating new branch...'
git checkout -b "merge-from-${before_ver}-to-${after_ver}"

echo '+ Merging upstream. It would cause confilicts...'
set +e
git merge upstream --no-commit
merge_exit=$?
set -e

echo '+ Updating version constants...'
before_ver_regex="${before_ver//./\\.}"
files_including_vim_version=(./README.md ./wasm/vimwasm.ts ./wasm/README.md)
sed -i '' -E "s/${before_ver_regex}/${after_ver}/" "${files_including_vim_version[@]}"

if [[ "$merge_exit" == 0 ]]; then
    git add "${files_including_vim_version[@]}"
    echo '+ Merge succeeded. Please check diff and create a merge commit by `git commit`'
else
    echo '+ Merge failed due to conflict. Please resolve conflict and create a merge commit by `git commit`'
fi
echo "+ After you create the merge commit, please run './build.sh merge-finish' to finish the work"
exit $merge_exit
