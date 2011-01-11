require 'rubygems'
require 'strongspace'
require 'strongspace/command'
require 'strongspace/commands/base'
require 'strongspace/commands/auth'

require File.expand_path("../lib/rsync_command", File.dirname(__FILE__))


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
      @rsync_command.version
    end

    it "should list no profiles if the configuration file doesn't exist" do
      @rsync_command.stub!(:configuration_file).and_return("/tmp/j")
      @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
      @rsync_command.list.count.should == 0
    end

    it "should should fail to load a malformed config file" do
      config_mock = "/tmp/RsyncBackup.config.#{Process.pid}"

      File.open(config_mock, 'w') { |f| f.write '''
        ---
        pro3files:
          iPhoto:
            strongspace_path: /strongspace/jmancuso/iPhoto
            local_source_path: /Users/jmancuso/Pictures
          iTunes:
            strongspace_path: /strongspace/jmancuso/iTunes
            local_source_path: /Users/jmancuso/Music
        config_version: 0.0.2
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

        File.open(@config_mock, 'w') { |f| f.write "
          ---
          profiles:
            iPhoto:
              strongspace_path: /strongspace/jmancuso/iPhoto
              local_source_path: /Users/jmancuso/Pictures
            tmp_test:
              strongspace_path: /tmp/RsyncBackup.dst.#{Process.pid}
              local_source_path: /tmp/RsyncBackup.src.#{Process.pid}
          config_version: 0.0.2
        "}
        @rsync_command.stub!(:configuration_file).and_return(@config_mock)

      end

      after do
        FileUtils.rm_rf(@config_mock)
      end

      it "should list the current backup profiles" do
        @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
        @rsync_command.should_receive(:display).with("iPhoto")
        @rsync_command.should_receive(:display).with("tmp_test")
        @rsync_command.list
      end

      it "should be able to create a new rsync profile" do
        profile_data = {'foo' => {'local_source_path' => '/tmp/location', 'strongspace_path' => "/strongspace/test" }}

        @rsync_command.stub!(:ask_for_new_rsync_profile).and_return(profile_data)
        @rsync_command.stub!(:args).and_return(['foo'])
        @rsync_command.create

        @rsync_command.should_receive(:display).with("Available rsync backup profiles:")
        @rsync_command.should_receive(:display).with("iPhoto")
        @rsync_command.should_receive(:display).with("tmp_test")
        @rsync_command.should_receive(:display).with("foo")
        @rsync_command.list
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
        FileUtils.mkdir_p("/tmp/RsyncBackup.src.#{Process.pid}")
        File.open("/tmp/RsyncBackup.src.#{Process.pid}/test_file", 'w') { |f| f.write "
         foo bar
        "}

        FileUtils.mkdir_p("/tmp/RsyncBackup.dst.#{Process.pid}")
        @rsync_command.stub!(:args).and_return(['tmp_test'])

        @rsync_command.stub!(:rsync_command).and_return("rsync -a /tmp/RsyncBackup.src.#{Process.pid}/ /tmp/RsyncBackup.dst.#{Process.pid}/")

        @rsync_command.run.should == true
        File.exist?("/tmp/RsyncBackup.dst.#{Process.pid}/test_file").should == true

        FileUtils.rm_rf("/tmp/RsyncBackup.src.#{Process.pid}")
        FileUtils.rm_rf("/tmp/RsyncBackup.dst.#{Process.pid}")
      end

    end

  end

end