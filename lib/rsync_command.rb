require 'yaml'
require 'find'
require 'digest'

begin
  require 'open4'
rescue LoadError
  raise "open4 gem is missing.  Please install open4: sudo gem install open4"
end

if not (RUBY_PLATFORM =~ /mswin32|mingw32|-darwin\d/)
  begin
    require 'cronedit'
  rescue LoadError
    raise "cronedit gem is missing.  Please install open4: sudo gem install cronedit"
  end
end

module Strongspace::Command
  class Rsync < Base

    def setup

      Strongspace::Command.run_internal("auth:check", nil)

      display "Creating a new strongspace backup profile"
      puts
      display "Location to backup [#{default_backup_path}]: ", false
      location = ask(default_backup_path)
      display "Strongspace destination space [#{default_strongspace_destination}]: ", false
      strongspace_destination = ask(default_strongspace_destination)
      puts "Setting up backup from #{location} -> #{strongspace_destination}"

      File.open(configuration_file, 'w+' ) do |out|
        YAML.dump({'local_library_path' => location, 'strongspace_path' => "/strongspace#{strongspace_destination}"}, out)
      end

    end
    
    def echo
      puts command_name
    end
    
    def backup

      while not load_configuration
        setup
      end

      if not (create_pid_file(command_name, Process.pid))
        display "The backup process is already running"
        exit(1)
      end

      if not new_digest = has_library_changed?(@local_library_path)
        launched_by = `ps #{Process.ppid}`.split("\n")[1].split(" ").last

        if not launched_by.ends_with?("launchd")
          display "backup target has not changed since last backup attempt."
        end
        delete_pid_file(command_name)
        exit(0)
      end

      rsync_command = "#{rsync_binary} -e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1' --delete -avr #{@local_library_path}/ #{strongspace.username}@#{strongspace.username}.strongspace.com:#{@strongspace_path}/"

      restart_wait = 10
      num_failures = 0

      while true do
        status = Open4::popen4(rsync_command) do
          |pid, stdin, stdout, stderr|

          display "\n\nStarting Strongspace Backup: #{Time.now}"

          if not (create_pid_file("#{command_name}.rsync", pid))
            display "Couldn't start backup sync, already running?"
            eixt(1)
          end

          sleep(5)
          threads = []


          threads << Thread.new(stderr) { |f|
            while not f.eof?
              line = f.gets.strip
              if not line.starts_with?("rsync: failed to set permissions on") and not line.starts_with?("rsync error: some files could not be transferred (code 23) ") and not line.starts_with?("rsync error: some files/attrs were not transferred (see previous errors)")
                puts "error: #{line}" unless line.blank?
              end
            end
          }

          threads << Thread.new(stdout) { |f|
            while not f.eof?
              line = f.gets.strip
              puts "#{line}" unless line.blank?
            end
          }


          threads.each { |aThread|  aThread.join }

        end

        delete_pid_file("#{command_name}.rsync")

        if status.exitstatus == 23 or status.exitstatus == 0
          num_failures = 0
          write_successful_backup_hash(new_digest)
          display "Successfully backed up at #{Time.now}"
          delete_pid_file(command_name)
          exit(0)
        else
          display "Error backing up - trying #{3-num_failures} more times"
          num_failures += 1
          if num_failures == 3
            puts "Failed out with status #{status.exitstatus}"
            exit(1)
          else
            sleep(1)
          end
        end

      end

      delete_pid_file(command_name)
    end

    def schedule_backup
      if not File.exist?(logs_folder)
        FileUtils.mkdir(logs_folder)
      end

      if running_on_windows?
        error "Scheduling currently isn't supported on Windows"
        return
      end

      if running_on_a_mac?
        plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE plist PUBLIC -//Apple Computer//DTD PLIST 1.0//EN
        http://www.apple.com/DTDs/PropertyList-1.0.dtd >
        <plist version=\"1.0\">
        <dict>
            <key>Label</key>
            <string>com.strongspace.#{command_name}</string>
            <key>Program</key>
            <string>#{$PROGRAM_NAME}</string>
            <key>ProgramArguments</key>
            <array>
              <string>strongspace</string>
              <string>rsync:backup</string>
            </array>
            <key>KeepAlive</key>
            <false/>
            <key>StartInterval</key>
            <integer>60</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>#{log_file}</string>
            <key>StandardErrorPath</key>
            <string>#{log_file}</string>
        </dict>
        </plist>"

        file = File.new(launchd_plist_file, "w+")
        file.puts plist
        file.close

        r = `launchctl load -S aqua #{launchd_plist_file}`
        if r.strip.ends_with?("Already loaded")
          error "This task is aready scheduled, unload before scheduling again"
          return
        end
        display "Scheduled #{command_name} to be run continuously"
      else  # Assume we're running on linux/unix
        begin
          CronEdit::Crontab.Add  "strongspace-#{command_name}", "0,5,10,15,20,25,30,35,40,45,52,53,55 * * * * #{$PROGRAM_NAME} rsync:backup >> #{log_file} 2>&1"
        rescue Exception => e
          error "Error setting up schedule: #{e.message}"
        end
        display "Scheduled #{command_name} to be run every five minutes"
      end



    end

    def unschedule_backup
      if running_on_windows?
        error "Scheduling currently isn't supported on Windows"
        return
      end

      if running_on_a_mac?
        `launchctl unload #{launchd_plist_file}`
        FileUtils.rm(launchd_plist_file)
      else  # Assume we're running on linux/unix
        CronEdit::Crontab.Remove "strongspace-#{command_name}"
      end

      display "Unscheduled continuous backup"

    end

    def backup_scheduled?
      r = `launchctl list com.strongspace.#{command_name}`
      if r.ends_with?("unknown response")
        display "#{command_name} isn't currently scheduled"
      else
        display "#{command_name} is currently scheduled for continuous backup"
      end
    end

    def logs
      if File.exist?(log_file)
        if running_on_windows?
          error "Scheduling currently isn't supported on Windows"
          return
        end
        if running_on_a_mac?
          `open -a Console.app #{log_file}`
        else
          system("/usr/bin/less less #{log_file}")
        end
      else
        display "No log file has been created yet, run strongspace rsync:setup to get things going"
      end
    end

    private


    def command_name
      "RsyncBackup"
    end

    def has_library_changed?(path)
      digest = recursive_digest(path)
      changed = (existing_library_hash.strip != digest.strip)
      if changed
        return digest
      else
        return nil
      end
    end

    def write_successful_backup_hash(digest)
      file = File.new(library_hash_file, "w+")
      file.puts "#{digest}"
      file.close
    end


    def recursive_digest(path)
      digest = Digest::SHA2.new(512)

      Find.find(path) do |entry|
        if File.file?(entry) or File.directory?(entry)
          stat = File.stat(entry)
          digest.update("#{entry} - #{stat.mtime} - #{stat.size}")
        end
      end

      return digest.to_s
    end

    def existing_library_hash
      if File.exist?(library_hash_file)
        f = File.open(library_hash_file)
        existing_hash = f.gets
        f.close
        return existing_hash
      end

      return ""
    end



    def load_configuration
      begin
        @configuration_hash = YAML::load_file(configuration_file)
      rescue
        return nil
      end

      @local_library_path = @configuration_hash['local_library_path']
      @strongspace_path = @configuration_hash['strongspace_path']

    end

    def log_file
      "#{logs_folder}/#{command_name}.log"
    end

    def logs_folder
      if running_on_a_mac?
        "#{home_directory}/Library/Logs/Strongspace/"
      else
        "#{home_directory}/.strongspace/logs"
      end
    end

    def launchd_plist_file
      "#{launchd_agents_folder}/com.strongspace.#{command_name}.pist"
    end

    def library_hash_file
      "#{home_directory}/.strongspace/#{command_name}.lastbackup"
    end

    def configuration_file
      "#{home_directory}/.strongspace/#{command_name}.config"
    end

    def rsync_binary
      "rsync"
      #"#{home_directory}/.strongspace/bin/rsync"
    end

    def default_backup_path
      "#{home_directory}/Documents"
    end

    def default_strongspace_destination
      "/#{strongspace.username}/home/backup"
    end

  end
end
