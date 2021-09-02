# Ansible Automation


## Usage


  1. Prepare ansible control node `pimaster` following these [instructions](./pimaster.md)
  
  2. Install Ansible requirements:

     ```
     ansible-galaxy install -r requirements.yml
     ```
    
  3. Adjust `inventory.yml` inventory file to meet your cluster configuration
  
  4. Configure cluster firewall (`gateway` node)
     
     Run the playbook:

     ```
     ansible-playbook gateway.yml
     ```
  5. Configure cluster nodes (`node1-node4` nodes)

     Run the playbook:

     ```
     ansible-playbook node.yml
     ```
