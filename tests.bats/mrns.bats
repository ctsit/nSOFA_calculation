function search_for_mrns {
    TEST=$(git diff --cached| grep "^+.*[0-9]\{5\}")
    RESULT=$?
    echo $TEST
    return $RESULT
}

@test "the git stage has nothing that looks like an MRN" {
  run search_for_mrns
  echo "output = ${output}"
  [ "${status}" -eq 1 ]
}
