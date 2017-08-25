# Launches a Vagrant VM and builds vRouter.
# Run this script from the directory that contains Vagrantfile.

# We don't use CONTROLLER_BRANCH and GENERATEDS_BRANCH because we only build kernel module for now

if [ "$#" -ne 5 ]; then
    echo "Usage: TOOLS_BRANCH CONTROLLER_BRANCH VROUTER_BRANCH GENERATEDS_BRANCH SANDESH_BRANCH"
    exit 1
fi

vagrant up
vagrant ssh -c "
ls
cd contrail-vrouter
pushd tools
  pushd build
    git checkout $1 --
  popd
  pushd sandesh
    git checkout $5 --
  popd
popd
pushd vrouter
  git checkout $3 --
popd
scons vrouter/vrouter.ko"
retcode=$?
vagrant halt
vagrant destroy -f
exit $retcode
