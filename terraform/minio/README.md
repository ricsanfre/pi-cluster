# Minio Terraform Configuration Module

This Terraform module uses the [aminueza/terraform-provider-minio](https://github.com/aminueza/terraform-provider-minio) provider to configure:

- **S3 Buckets**: Create and manage Minio S3 buckets used by Kubernetes services (Loki, Tempo, Longhorn, Velero, Restic, Barman)
- **IAM Policies**: Define access control policies for each service user
- **IAM Users**: Create users with access keys (secret keys configured separately via Minio CLI or Ansible)
- **Policy Attachments**: Bind policies to users for granular access control

## Project Structure

```
terraform/minio/
├── main.tf                  # Resource definitions (buckets, users, policies)
├── provider.tf              # Minio provider configuration
├── variables.tf             # Variable definitions with directory paths
├── outputs.tf               # Terraform outputs
├── terraform.tfvars.example # Variable overrides template
├── README.md                # This file
└── resources/
    ├── buckets/
    │   ├── loki.json        # Loki bucket configuration
    │   ├── tempo.json       # Tempo bucket configuration
    │   ├── longhorn.json    # Longhorn bucket configuration
    │   ├── velero.json      # Velero bucket configuration
    │   └── restic.json      # Restic bucket configuration
    ├── users/
    │   ├── loki.json        # Loki user configuration
    │   ├── tempo.json       # Tempo user configuration
    │   ├── longhorn.json    # Longhorn user configuration
    │   ├── velero.json      # Velero user configuration
    │   ├── restic.json      # Restic user configuration
    │   └── barman.json      # Barman user configuration
    └── policies/
        ├── loki.json        # Loki IAM policy
        ├── tempo.json       # Tempo IAM policy
        ├── longhorn.json    # Longhorn IAM policy
        ├── velero.json      # Velero IAM policy
        ├── restic.json      # Restic IAM policy
        └── barman.json      # Barman IAM policy
```

## Prerequisites

1. **Minio Instance**: Running and accessible Minio S3 server
2. **Admin Credentials**: Root access key and secret key for Minio
3. **Terraform**: Version >= 1.0
4. **Provider**: aminueza/terraform-provider-minio >= 2.0

## Configuration Files

### resources/buckets/*.json
Individual bucket configuration files. Each file is named after the bucket key and contains:
- `name`: Bucket name (string, required)
- `versioning`: Enable versioning (boolean, optional, default: false)
- `object_lock`: Enable object lock (boolean, optional, default: false)
- `description`: Bucket description (string, optional)

Example: `resources/buckets/loki.json`
```json
{
  "name": "k3s-loki",
  "versioning": false,
  "object_lock": false,
  "description": "Loki logs storage"
}
```

### resources/users/*.json
Individual user configuration files. Each file is named after the user key and contains:
- `access_key`: Username/access key (string, required)
- `policies`: List of policy names to attach (list of strings, optional)
- `description`: User description (string, optional)

Example: `resources/users/loki.json`
```json
{
  "access_key": "loki",
  "policies": ["loki"],
  "description": "Loki S3 user"
}
```

### resources/policies/*.json
Individual policy configuration files. Each file is named after the policy key and contains:
- `name`: Policy name (string, required)
- `description`: Policy description (string, optional)
- `statements`: List of IAM policy statements with `effect`, `actions`, and `resources`

Example: `resources/policies/loki.json`
```json
{
  "name": "loki",
  "description": "Loki access policy",
  "statements": [
    {
      "effect": "Allow",
      "actions": [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject"
      ],
      "resources": [
        "arn:aws:s3:::k3s-loki",
        "arn:aws:s3:::k3s-loki/*"
      ]
    }
  ]
}
```

### provider.tf
Configures the Minio provider with:
- Server endpoint (hostname:port)
- Region
- SSL/TLS settings
- Root credentials

### variables.tf
Defines input variables for:
- Minio connection details
- File paths for resource JSON files (with defaults pointing to `resources/` directory)
- Override variables for customizing loaded configurations

### main.tf
Implements resources for:
- `minio_s3_bucket`: Creates S3 buckets from JSON configuration
- `minio_iam_policy`: Creates IAM policies from JSON configuration
- `minio_iam_user`: Creates users from JSON configuration
- `minio_iam_user_policy_attachment`: Attaches policies to users

### outputs.tf
Exposes:
- Created buckets with ARNs
- Policies configuration
- Users and their assigned policies
- User-service mapping
- Configuration summary

### terraform.tfvars.example
Template for configuration with:
- Minio server endpoint
- Credentials
- Custom file paths (optional)
- Override configurations (optional)

## Usage

### 1. Initialize Terraform

```bash
cd terraform/minio/
terraform init
```

### 2. Configure Variables

Set environment variables or create `terraform.tfvars` from the template:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars`:

```bash
export TF_VAR_minio_admin_user="root"
export TF_VAR_minio_admin_password="your_password"
export TF_VAR_minio_endpoint="s3.picluster.ricsanfre.com:9000"
```

### 3. Add/Modify Resources via Individual Files

#### Add a New Bucket

Create a new file `resources/buckets/mimir.json`:

```json
{
  "name": "k3s-mimir",
  "versioning": false,
  "object_lock": false,
  "description": "Mimir metrics storage"
}
```

#### Add a New User

Create a new file `resources/users/mimir.json`:

```json
{
  "access_key": "mimir",
  "policies": ["mimir"],
  "description": "Mimir S3 user"
}
```

#### Add a New Policy

Create a new file `resources/policies/mimir.json`:

```json
{
  "name": "mimir",
  "description": "Mimir access policy",
  "statements": [
    {
      "effect": "Allow",
      "actions": [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject"
      ],
      "resources": [
        "arn:aws:s3:::k3s-mimir",
        "arn:aws:s3:::k3s-mimir/*"
      ]
    }
  ]
}
```

#### Remove a Resource

Simple delete the corresponding JSON file:

```bash
rm resources/buckets/mimir.json
rm resources/users/mimir.json
rm resources/policies/mimir.json
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Apply Configuration

```bash
terraform apply
```

### 6. Get Outputs

```bash
terraform output
terraform output -json user_service_mapping  # View user configurations
```

## Advanced Configuration

### Using Custom Directory Paths

In `terraform.tfvars`:

```hcl
buckets_dir = "/path/to/custom/buckets"
users_dir = "/path/to/custom/users"
policies_dir = "/path/to/custom/policies"
```

### Merging Files and Override Configurations

Combine individual JSON files with terraform.tfvars overrides:

**resources/buckets/loki.json** (base):
```json
{
  "name": "k3s-loki",
  "versioning": false,
  "object_lock": false,
  "description": "Loki logs storage"
}
```

**terraform.tfvars** (adds additional bucket):
```hcl
minio_buckets_override = {
  "mimir" = {
    name        = "k3s-mimir"
    versioning  = false
    object_lock = false
    description = "Mimir metrics storage"
  }
}
```

Result: Both `loki` (from file) and `mimir` (from override) buckets created.

## Migration from Ansible Role

This Terraform module migrates the Ansible role configuration from [ricsanfre.minio](https://github.com/ricsanfre/ansible-role-minio):

### Ansible Approach (Old)
- Configured Minio on baremetal server via Ansible
- Created buckets, users, and policies via Ansible tasks
- Configuration stored in playbook variables

### Terraform Approach (New)
- Uses declarative infrastructure-as-code
- Configuration stored in JSON resource files
- Provider manages Minio API calls
- Repeatable and idempotent deployments
- Easy to version control and audit

### Mapping from vault.yml.j2

The module creates users and buckets from `vault.yml.j2`:

| Service | User | Bucket | Source |
|---------|------|--------|--------|
| Loki | loki | k3s-loki | vault.yml.j2: `minio.loki` |
| Tempo | tempo | k3s-tempo | vault.yml.j2: `minio.tempo` |
| Longhorn | longhorn | k3s-longhorn | vault.yml.j2: `minio.longhorn` |
| Velero | velero | k3s-velero | vault.yml.j2: `minio.velero` |
| Restic | restic | restic | vault.yml.j2: `minio.restic` |
| Barman | barman | barman | vault.yml.j2: `minio.barman` |

## Service Users and Buckets
| Barman | barman | barman | PostgreSQL backups |

## Policy Definitions

Each user has a dedicated policy with minimal required permissions:

### Loki Policy
```json
{
  "s3:DeleteObject",
  "s3:GetObject",
  "s3:ListBucket",
  "s3:PutObject"
}
```

### Tempo Policy
```json
{
  "s3:DeleteObject",
  "s3:GetObject",
  "s3:ListBucket",
  "s3:PutObject",
  "s3:GetObjectTagging",
  "s3:PutObjectTagging"
}
```

Similar minimal policies defined for Longhorn, Velero, Restic, and Barman.

## Credentials Management

### User Creation
Terraform creates IAM users with their access key (username). Users are created without initial secret keys.

### Secret Key Configuration
Secret keys must be set separately using one of these methods:

1. **Minio CLI** (post-deployment)
   ```bash
   mc admin user svcacct add <minio_alias> <username> <secretkey>
   ```

2. **Ansible Role Integration** (ricsanfre.minio)
   The role can set credentials using vault.yml.j2 variables after Terraform provisioning

3. **Manual API Calls**
   Use Minio's REST API with admin credentials to configure user secrets

### Admin Credentials
Admin credentials (root access key/secret) are:
- Required by Terraform provider to create resources
- Should be stored securely (environment variables, Terraform Cloud, etc.)
- Never committed to version control
- Consider using temporary credentials with limited TTL for production

## Troubleshooting

### SSL Certificate Issues
If using self-signed certificates, set `minio_ssl_verify = false` in terraform.tfvars

### Connection Issues
Verify Minio endpoint is accessible:
```bash
curl -k https://s3.picluster.ricsanfre.com:9000
```

### Policy Errors
Ensure IAM policy JSON is valid using:
```bash
terraform validate
```

## Integration with Kubernetes

Terraform creates users and policies. Secret keys must be provisioned separately and then used to create Kubernetes Secrets.

### Step 1: Get Created Users
```bash
terraform output -json user_service_mapping
```

### Step 2: Set Secret Keys
After setting secret keys via Minio CLI or Ansible, create Kubernetes Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio-loki-credentials
  namespace: loki
type: Opaque
stringData:
  access_key_id: loki
  secret_access_key: <set_via_minio_cli_or_ansible>
```

### Integration Flow
1. **Terraform**: Create buckets, policies, and users
2. **Ansible role (ricsanfre.minio)** OR **Minio CLI**: Set user secret keys
3. **Kubernetes**: Retrieve credentials and create Secrets
4. **Applications**: Mount Secrets as environment variables

## References

- [aminueza/terraform-provider-minio Documentation](https://registry.terraform.io/providers/aminueza/minio/latest/docs)
- [Minio Client Documentation](https://docs.min.io/minio/baremetal/)
- [AWS IAM Policy Format](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html)
- [Pi Cluster Minio Documentation](../../docs/_docs/minio.md)
