# Cookbook Name:: sysctl
# Provider:: sysctl
# Author:: Jesse Nelson <spheromak@gmail.com>
#
# Copyright 2011, Jesse Nelson
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require "chef/mixin/command.rb"
include Chef::Mixin::Command

def initialize(*args)
  super
  status, output, error_message = output_of_command("which sysctl", {})
  unless status.exitstatus == 0
    Chef::Log.info "Failed to locate sysctl on this system: STDERR: #{error_message}"
    Command.handle_command_failures(status, "STDOUT: #{output}\nSTDERR: #{error_message}")
  end

  # setup a config file
  @config_file = file "/etc/sysconfig" do
    action :nothing
    owner "root"
    group "root"
  end

  @sysctl = output.chomp
end

# sysctl -n -e  only works on linux  (-e at least is missing on mac)
# side effect is that these calls will always try to set/write on other platforms. 
# This is ok for now, but prob need to do detection at some point.
# TODO: Make this work on other platforms better
def load_current_resource
  # quick & dirty os detection
  @sysctl_args = case node.os
  when "GNU/Linux","Linux","linux"
    "-n -e"
  else 
    "-n"
  end
  
  # clean up value whitespace when its a string
  @new_resource.value.strip!  if @new_resource.value.class == String

  # find current value
  status, @current_value, error_message = output_of_command(
      "#{@sysctl} #{@sysctl_args} #{@new_resource.name}", {:ignore_failure => true})

end

action :set do
  # heavy handed type enforcement only wnat to write if they are different  ignore inner whitespace
  if @current_value.to_s.strip.split != @new_resource.value.to_s.strip.split
    # run it
    run_command( { :command => "#{@sysctl} #{@sysctl_args} -w #{@new_resource.name}='#{@new_resource.value}'" }  )

    # save to node obj if we were asked to
    node.sysctl["#{@new_resource.name}"]  = @new_resource.value if @new_resource.save == true

    # let chef know its done
    @new_resource.updated_by_last_action  true
  end
end

action :write do 
  entries = "# content managed by chef local changes will be overwritten"
  # walk the collecton
  run_context.resource_collection.each do |resource|
    if resource.is_a? Chef::Resource::Sysctl
      entries << "#{resource.name} = '#{resource.value}" if resource.action.include?(:write)
    end
  end

  @config_file.content = entries
  Chef::Log.info @config_file.inspect 
end

