Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-22.04"
  config.vm.boot_timeout = 900
  config.ssh.username = ENV.fetch("VAGRANT_SSH_USER", "vagrant")

  config.vm.provider "virtualbox" do |vb|
    vb.gui = false
  end

  servers = [
    { name: "lb-01",         ip: "192.168.56.10", memory: 512,  cpus: 1 },
    { name: "web-01",        ip: "192.168.56.11", memory