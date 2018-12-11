#!/usr/bin/env bash

# exit on any error
set -e

KUBEONE_ROOT=$(dirname "${BASH_SOURCE}")/..
BUILD_PATH=${KUBEONE_ROOT}/_build
TEST_TIMEOUT=${TEST_TIMEOUT:-10m}
export KUBECONFIG=${KUBECONFIG:-${HOME}/.kube/config}

# Make sure KUBEONE_CONFIG_FILE is properly set
if [[ -z ${KUBEONE_CONFIG_FILE} ]]; then
    echo "Please export KUBEONE_CONFIG_FILE in your env"
    exit 1
fi

# Make sure TFJSON is set
if [[ -z ${TFJSON} ]]; then
    echo "[WARNING] Please export TFJSON in your env if you use terraform for infrastructure deployment"
fi

KUBERNETES_VERSION=${KUBERNETES_VERSION:-$(grep 'kubernetes:' ${KUBEONE_CONFIG_FILE} | sed 's/[:[:alpha:]|(|[:space:]]//g'| sed "s/['\"]//g")}

create_kubeconfig() {
  echo "creating kubeconfig"
  mkdir -p ${HOME}/.kube
  if [[ -z ${TFJSON} ]]; then
    kubeone kubeconfig $(KUBEONE_CONFIG_FILE) > ${KUBECONFIG}
  else
    kubeone kubeconfig --tfjson ${TFJSON} ${KUBEONE_CONFIG_FILE} > ${KUBECONFIG}
  fi
}

# Start e2e conformance tests
start_tests() {
  echo "start e2e tests"

  export KUBERNETES_CONFORMANCE_TEST=y
  export SKIP="Alpha|\[(Disruptive|Feature:[^\]]+|Flaky)\]"

  version=""

  echo "get kubetest"
  go get -u k8s.io/test-infra/kubetest

  mkdir -p ${BUILD_PATH}
  (
    cd ${BUILD_PATH}

    # check if kubernetes in the same version already exists
    if [ -f "./kubernetes/version" ];then
      version=$(head -n 1 ./kubernetes/version)
      if [ "v${KUBERNETES_VERSION}" != "${version}" ]; then
        rm -rf ./kubernetes
        kubetest --extract=v${KUBERNETES_VERSION}
        rm kubernetes.tar.gz
      fi
    else
      kubetest --extract=v${KUBERNETES_VERSION}
      rm kubernetes.tar.gz
    fi

    cd ./kubernetes
    kubetest --provider=skeleton \
         --test \
         --ginkgo-parallel \
         --timeout=${TEST_TIMEOUT} \
         --test_args="--ginkgo.focus=\[NodeConformance\] --ginkgo.skip=${SKIP} "
  )
}
