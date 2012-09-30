puppetha
========

RoR + DynamoDB + AWS based puppet HA implementation


Some helpful notes (I hope) and quick cheats can be found here


Client Initialization:

1. New client instance connects to the elastic IP/name of the nginx HA cluster to the puppetizer SSL port (https://puppetmaster.XXX.com:8080) and indicating itself as a client
2. nginx node forwards the request to one of the healthy Puppetizer backends
3. Puppetizer does the following:
    # query AWS using API to check if the client is allowed to be added

is this client in my account at all ? 

    # generates a new client private key/certificate pair signed with the any healthy puppet master CA from the backend

    # sends the puppet master address:port (https://puppetmaster[0-9].XXX.com:814[0-9]) to make a first/test connection, certificate/key pair and the base CA cert back

4. Client connects to the puppet master address in the test mode ( puppet --test )

5. A puppet master executes the ENC script (http://docs.puppetlabs.com/guides/external_nodes.html) which does the following:
    # queries AWS using API to check if this node is allowed to be added
    # gets the node's security group name(s) from AWS using API
    # connects to the backend and use the node name and/or the security group as a key to get the config(s)
    # generates a YAML hash from the config(s)

6. Client receives all the configs and the nginx HA cluster elastic IP/name:port (https://puppetmaster.XXX.com:8041)

7. puppet service executes (service puppetd start) and connects to the elastic IP/name of the nginx HA cluster (https://puppetmaster.XXX.com:8041)
6. nginx forwards the request to any healthy puppet master node

Master initialization:
1. A new puppetmaster instance connects to the elastic IP/name of the nginx HA cluster to the puppetizer SSL port (https://puppetmaster.XXX.com:8080) indicating itself as a puppetmaster
2. nginx node forwards the request to one of the healthy Puppetizer backends
3. Puppetizer does the following:
   # query AWS using API to check if the client is allowed to be a master
   # generates a new puppetmaster CA private key/certificate pair signed with the base CA obtained from the backend DB
   # generates a new leaf private key/certificate pair signed with the just generated puppetmaster CA
   # adds this CA cert and the leaf cert to the backend DB
   # registers the new master node on all the nginx nodes (adds the new master IP to the upstream list) an adds puppetmaster CA cert, leaf cert and their CRL's
   # sends the pair back to the master
4. The master instance gets the certificate/key pair

nginx cluster nodes:
   # use Linux HA heartbeat package to identify unhealthy primary node and transfer the Elastic IP to the healthy node
   # the current primary node monitors the load on the masters (e.g. using number of connection/clients) and spins new nodes when needed
   # updates hot standby nodes with the current config

Puppetizer hosts:
   # if security is not important can be ran on the same hosts as puppetmasters

