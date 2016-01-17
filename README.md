This is not a generic bootstrap script and may be dangerous to
execute. Use this at your own risk.

# PARTITION_SCHEMES

you can use two different partition schemes
 * raid (/dev/sda and /dev/sdb)
 * singledisk (/dev/sda)


# Ansible

while in gentoo-bootstrap dir run: 

``` 
ssh-copy-id somehost
echo "somehost" > ansible/inventory
ansible-playbook -i ansible/inventory ./ansible/setup-vm-host.yml -v
```

when the script finishes you have gentoo installed on the remote host somehost 
see playbook for customisations

