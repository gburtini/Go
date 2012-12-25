# copies ssh key to remote host $1 to set up ssh keys.
echo "Setting up ssh key on $1 (:~/.ssh/authorized_keys)"
cat ~/.ssh/id_rsa.pub | ssh $1 'sh -c "cat - >>~/.ssh/authorized_keys"'
