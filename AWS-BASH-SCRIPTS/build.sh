#!/bin/bash
apt update
echo "install dotnet"
apt install -y aspnetcore-runtime-6.0 # for run only
#apt install -y dotnet-sdk-6.0 #for build and run
#apt install unzip -y

# Install aws CodeDeploy agent
cd /tmp
apt install -y ruby-full wget
wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
chmod +x ./install
./install auto
service codedeploy-agent start


