# Developer Notes

## Automated Testing

Developers on this project should enable automated testing to detect certain errors before making commits. To use the automated testing tools included in this repo, install the [bats-core](https://github.com/bats-core/bats-core#installation) test framework, and then enable a pre-commit hook to run the included tests.

To enable the pre-commit hook, run these commands from the root of this repository:

```bash
mkdir .git/hooks
ln -s ../../pre-commit.sh .git/hooks/pre-commit
```
