Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-22.04"
  config.vm.boot_timeout = 900

  config.vm.provider "virtualbox" do |vb|
    vb.gui = true
  end

  servers = [
    {
      name: "lb-01",
      ip: "192.168.56.10",
      memory: 1024,
      cpus: 1
    },
    {
      name: "web-01",
      ip: "192.168.56.11",
      memory: 1024,
      cpus: 1
    },
    {
      name: "web-02",
      ip: "192.168.56.12",
      memory: 1024,
      cpus: 1
    },
    {
      name: "app-01",
      ip: "192.168.56.13",
      memory: 1024,
      cpus: 1
    },
    {
      name: "ci-01",
      ip: "192.168.56.14",
      memory: 2048,
      cpus: 2
    }
  ]

  servers.each do |server|
    config.vm.define server[:name] do |node|
      node.vm.hostname = server[:name]

      node.vm.network "private_network", ip: server[:ip]

      node.vm.provider "virtualbox" do |vb|
        vb.name = "automation-alchemy-#{server[:name]}"
        vb.memory = server[:memory]
        vb.cpus = server[:cpus]
      end

      node.vm.provision "shell", inline: <<-SHELL
        sudo apt-get update -y
        sudo apt-get install -y python3
      SHELL
    end
  end
end