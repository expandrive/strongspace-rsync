require 'rubygems'
require 'strongspace'
require 'strongspace/command'
require 'strongspace/commands/base'
require 'strongspace/commands/auth'

require File.expand_path("../init.rb", File.dirname(__FILE__))


def prepare_command(klass)
  command = klass.new(['--app', 'myapp'])
  command.stub!(:args).and_return([])
  command.stub!(:display)
  command
end



module Strongspace::Command
  describe Rsync do

    before do
      @rsync_command = prepare_command(Rsync)
    end

    it "should print the current version" do
      @rsync_command.should_receive(:display).with("RsyncBackup v#{@rsync_command.version}")
      @rsync_command.version.should == StrongspaceRsync::VERSION
    end

    it "should list no profiles if the configuration file doesn't exist" do
      @rsync_command.stub!(:configuration_file).and_return("/tmp/j")
      @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
      @rsync_command.list.count.should == 0
    end

    it "should should fail to load a malformed config file" do
      config_mock = "/tmp/RsyncBackup.config.#{Process.pid}"

      File.open(config_mock, 'w') { |f| f.write '''
        {
          "profi3les": [
            {
              "name": "iPhoto",
              "strongspace_path": "/strongspace/hemancuso/Public",
              "local_source_path": "/Users/jmancuso/Public",
              "last_successful_backup": "2011-01-21T09:35:56-05:00"
            },
            {
              "name": "iTunes",
              "strongspace_path": "/strongspace/hemancuso/anna",
              "local_source_path": "/Users/jmancuso/anna"
            }
          ],
          "config_version": "0.1.0"
        }
      '''}

      @rsync_command.stub!(:configuration_file).and_return(config_mock)
      @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
      @rsync_command.should_not_receive(:display).with("iPhoto")
      @rsync_command.should_not_receive(:display).with("iTunes")
      @rsync_command.list

      FileUtils.rm_rf(config_mock)

    end

    describe "with a configuration file" do

      before do
        @rsync_command = prepare_command(Rsync)

        @config_mock = "/tmp/RsyncBackup.config.#{Process.pid}"

        File.open(@config_mock, 'w') { |f| f.write '
          {
            "profiles": [
              {
                "name": "iPhoto",
                "strongspace_path": "/strongspace/hemancuso/Public",
                "local_source_path": "/Users/jmancuso/Public",
                "last_successful_backup": "2011-01-21T09:35:56-05:00"
              },
              {
                "name": "tmp_test",
                "strongspace_path": "/tmp/RsyncBackup.dst",
                "local_source_path": "/tmp/RsyncBackup.src"
              }
            ],
            "config_version": "0.1.0"
          }
        '}
        @rsync_command.stub!(:configuration_file).and_return(@config_mock)

      end

      after do
        FileUtils.rm_rf(@config_mock)
      end

      it "should list the current backup profiles" do
        @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
        @rsync_command.should_receive(:display).with("iPhoto")
        @rsync_command.should_receive(:display).with("tmp_test")
        @rsync_command.list.count.should == 2
      end

      it "should be able to create a new rsync profile" do
        profile_data = {'name' => 'foo', 'local_source_path' => '/tmp/location', 'strongspace_path' => "/strongspace/test" }

        @rsync_command.stub!(:ask_for_new_rsync_profile).and_return(profile_data)
        @rsync_command.stub!(:args).and_return(['foo'])
        @rsync_command.create

        @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
        @rsync_command.should_receive(:display).with("iPhoto")
        @rsync_command.should_receive(:display).with("tmp_test")
        @rsync_command.should_receive(:display).with("foo")
        @rsync_command.list
      end

      it "should prevent profile name collisons" do
        @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
        @rsync_command.should_receive(:display).with("iPhoto")
        @rsync_command.should_receive(:display).with("tmp_test")
        @rsync_command.list
        @rsync_command.stub!(:args).and_return(['iPhoto'])
        @rsync_command.should_receive(:display).with("This backup name is already in use")
        @rsync_command.create
      end


      it "should be able to delete an rsync profile" do
        @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
        @rsync_command.should_receive(:display).with("iPhoto")
        @rsync_command.should_receive(:display).with("tmp_test")
        @rsync_command.list
        @rsync_command.stub!(:args).and_return(['iPhoto'])
        @rsync_command.should_receive(:display).with("iPhoto has been deleted")
        @rsync_command.delete
        @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
        @rsync_command.should_not_receive(:display).with("iPhoto")
        @rsync_command.should_receive(:display).with("tmp_test")
        @rsync_command.list
      end

      it "should correctly run a backup" do
        FileUtils.mkdir_p("/tmp/RsyncBackup.src")
        File.open("/tmp/RsyncBackup.src/test_file", 'w') { |f| f.write "
         foo bar
        "}

        FileUtils.mkdir_p("/tmp/RsyncBackup.dst")
        @rsync_command.stub!(:args).and_return(['tmp_test'])

        @rsync_command.stub!(:rsync_command).and_return("rsync -a /tmp/RsyncBackup.src/ /tmp/RsyncBackup.dst/")

        @rsync_command.run.should == true
        File.exist?("/tmp/RsyncBackup.dst/test_file").should == true

        FileUtils.rm_rf("/tmp/RsyncBackup.src")
        FileUtils.rm_rf("/tmp/RsyncBackup.dst")
      end

    end

  end

end