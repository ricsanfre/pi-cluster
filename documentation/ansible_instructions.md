# Ansible Automation


## Usage

First, you need to make sure you have K3s running on your Pi cluster. Instructions for doing so are in Episodes 2 and 3 (linked above).


  1. Prepare ansible control node `pimaster` following these [instructions](./pimaster.md)
  2. Install Ansible requirements:

     ```
     ansible-galaxy install -r requirements.yaml
     ```
    
  3. Copy the `example.hosts.ini` inventory file to `hosts.ini`. Make sure it has the `master` and `node`s configured correctly.
  
  5. Configure `gateway` node
     Run the playbook:

     ```
     ansible-playbook gateway.yaml
     ```