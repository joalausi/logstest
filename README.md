# Automation Alchemy

Automation Alchemy is a local DevOps automation project that provisions a multi-server infrastructure, deploys a containerized application, runs a CI/CD pipeline, and supports rollback to previous Docker image versions.

The project is designed to be reproducible from a clean state using Vagrant, Ansible, Docker, NGINX, Jenkins, and a local Docker Registry.

---

## Architecture

| VM | IP | Role |
|---|---:|---|
| `lb-01` | `192.168.56.10` | NGINX load balancer |
| `web-01` | `192.168.56.11` | Frontend container |
| `web-02` | `192.168.56.12` | Frontend container |
| `app-01` | `192.168.56.13` | Backend container |
| `ci-01` | `192.168.56.14` | Jenkins and local Docker Registry |

Application traffic flow:

```text
Browser
  ↓
lb-01:80
  ↓
web-01:8080 / web-02:8080
  ↓
app-01:3000
```

CI/CD flow:

```text
Jenkins
  ↓
Build backend and frontend Docker images
  ↓
Push images to local Docker Registry
  ↓
Deploy selected image tag with Ansible
  ↓
Run health checks
```

---

## Stack

- Vagrant
- VirtualBox
- Ansible
- Docker
- Local Docker Registry
- NGINX
- Jenkins
- Node.js backend
- NGINX static frontend

---

## Prerequisites

Recommended setup:

- Windows host
- VirtualBox
- Vagrant
- WSL Ubuntu
- Ansible installed inside WSL

Vagrant commands are intended to be run from Windows PowerShell.

Ansible commands are intended to be run from WSL Ubuntu.

Install the required Ansible collection if needed:

```bash
ansible-galaxy collection install community.general
```

---

## Project Structure

```text
.
├── Vagrantfile
├── Makefile
├── README.md
├── app/
│   ├── backend/
│   └── frontend/
├── ansible/
│   ├── inventory.ini
│   ├── site.yml
│   ├── deploy.yml
│   ├── rollback.yml
│   ├── group_vars/
│   └── roles/
├── ci/
│   ├── Jenkinsfile
│   └── jenkins/
└── scripts/
```

---

## Quick Start

### 1. Start the virtual machines

Run from PowerShell:

```powershell
vagrant up
```

Check VM status:

```powershell
vagrant status
```

Expected result:

```text
lb-01   running
web-01  running
web-02  running
app-01  running
ci-01   running
```

---

### 2. Sync Vagrant SSH keys for Ansible

Run from WSL inside the project directory:

```bash
make sync-keys
```

If the script is not executable:

```bash
chmod +x scripts/sync-vagrant-keys.sh
make sync-keys
```

---

### 3. Check Ansible connectivity

```bash
make ping
```

Expected result: all hosts return `SUCCESS`.

---

### 4. Provision the full infrastructure

```bash
make provision
```

This command:

- configures all VMs
- applies basic security settings
- enables UFW firewall
- installs Docker
- starts the local Docker Registry
- builds backend and frontend images
- pushes images to the local registry
- deploys backend and frontend containers
- configures NGINX load balancing
- configures Jenkins and creates the pipeline job

---

### 5. Verify the application

```bash
make app-test
```

Open the application in a browser:

```text
http://192.168.56.10
```

---

## Services

| Service | URL |
|---|---|
| Application | `http://192.168.56.10` |
| Backend health | `http://192.168.56.13:3000/health` |
| Registry catalog | `http://192.168.56.14:5000/v2/_catalog` |
| Jenkins | `http://192.168.56.14:8080` |

Jenkins local demo credentials:

```text
username: admin
password: admin
```

These credentials are only used for the local educational environment.

---

## Make Commands

| Command | Description |
|---|---|
| `make up` | Start Vagrant VMs |
| `make status` | Show VM status |
| `make sync-keys` | Copy Vagrant SSH keys into the WSL SSH directory |
| `make ping` | Test Ansible connectivity |
| `make provision` | Run full Ansible provisioning |
| `make registry-test` | Check the local Docker Registry |
| `make registry-smoke` | Push and pull a test image through the registry |
| `make app-test` | Run application health checks |
| `make image-tags` | Show available backend and frontend image tags |
| `make deployed-images` | Show currently deployed Docker image tags |
| `make rollback VERSION=<tag>` | Roll back the application to a previous image tag |
| `make jenkins-url` | Print Jenkins URL and credentials |
| `make jenkins-status` | Show Jenkins container status |
| `make jenkins-logs` | Show Jenkins container logs |
| `make destroy` | Destroy all Vagrant VMs |

---

## Application

The backend is a small Node.js service that exposes:

```text
/health
/metrics
```

The frontend is served by NGINX and displays basic infrastructure information. It calls the backend through the frontend container's internal NGINX proxy.

Frontend instances run on both `web-01` and `web-02`.

The load balancer on `lb-01` distributes traffic between both frontend servers.

---

## CI/CD Pipeline

Jenkins is automatically configured by Ansible.

The pipeline job is created from:

```text
ci/Jenkinsfile
```

Pipeline stages:

1. Checkout repository
2. Build backend and frontend Docker images
3. Tag images with the Jenkins build number
4. Push images to the local Docker Registry
5. Deploy images with Ansible
6. Run health checks

Images are pushed to:

```text
192.168.56.14:5000/automation-backend:<build_number>
192.168.56.14:5000/automation-frontend:<build_number>
```

The `latest` tag is also updated.

To run the pipeline:

1. Open Jenkins: `http://192.168.56.14:8080`
2. Open `automation-alchemy-deploy`
3. Click `Build Now`

---

## Rollback

Each Jenkins build creates versioned Docker image tags.

Example:

```text
automation-backend:3
automation-backend:4
automation-frontend:3
automation-frontend:4
```

Rollback does not rebuild images. It redeploys an existing image tag from the local registry.

Check available image tags:

```bash
make image-tags
```

Check currently deployed images:

```bash
make deployed-images
```

Rollback to version `3`:

```bash
make rollback VERSION=3
```

Return to version `4`:

```bash
make rollback VERSION=4
```

After rollback, health checks are executed automatically.

---

## Security Notes

The project includes basic VM security configuration:

- UFW firewall is enabled
- SSH is allowed on all VMs
- HTTP is exposed on the load balancer
- frontend ports are allowed only from the load balancer
- backend port is allowed only from frontend servers
- Jenkins and Docker Registry ports are exposed on the CI server

This setup is intended for a local educational environment, not for production use.

---

## Demo Flow

Recommended review demo:

```bash
make status
make ping
make provision
make app-test
make image-tags
make deployed-images
```

Open in browser:

```text
http://192.168.56.10
http://192.168.56.14:8080
```

Run Jenkins pipeline:

```text
automation-alchemy-deploy → Build Now
```

Then verify:

```bash
make image-tags
make deployed-images
make app-test
```

Rollback demo:

```bash
make rollback VERSION=3
make deployed-images

make rollback VERSION=4
make deployed-images
make app-test
```

---

## Troubleshooting

### Ansible cannot connect to VMs

Sync Vagrant SSH keys:

```bash
make sync-keys
make ping
```

---

### Vagrant VM boot timeout

Start VMs one by one:

```powershell
vagrant up lb-01
vagrant up web-01
vagrant up web-02
vagrant up app-01
vagrant up ci-01
```

If needed, increase `config.vm.boot_timeout` in `Vagrantfile`.

---

### Jenkins pipeline fails on checkout

Make sure the latest project files are pushed to the branch used in:

```text
ci/jenkins/casc.yaml
```

---

### Jenkins pipeline fails on deploy

Check Ansible connectivity:

```bash
make ping
```

Check Jenkins logs:

```bash
make jenkins-logs
```

---

### Registry does not contain expected image tags

Check image tags:

```bash
make image-tags
```

Run the Jenkins pipeline again or run full provisioning:

```bash
make provision
```

---

## Cleanup

Destroy all VMs:

```powershell
vagrant destroy -f
```