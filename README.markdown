Strongspace iTunes Backup plugin
================================

This is a plugin for the [Strongspace gem](https://github.com/expandrive/strongspace-ruby) to automatically backup your iTunes Library to Strongspace. Currently it only works on Mac but will support windows soon enough.


Installation
------------

Upgrade/Install the Strongspace gem to v0.0.9 or newer:
    `sudo gem install strongspace`

Install the Strongspace iTunes plugin
    `strongspace plugins:install git://github.com/expandrive/strongspace-itunes.git`

Now when you run `strongspace help` you will see these extra commands.

    === iTunes Backup
    itunes:backup                                     # Performs a backup of iTunes
    itunes:setup                                      # Create a backup profile for iTunes
    itunes:schedule_backup                            # Schedules continuous iTunes backup
    itunes:unschedule_backup                          # Unschedules continuous iTunes backup
    itunes:log                                       # Opens Console.app and shows the iTunes Backup log

This plugin assumes you have key based authentication already set up. To set up password-less key-based authentication first run `strongspace keys:add` to get it going.

Usage
-----

To get started just run
    `strongspace itunes:backup`

This will kick off the `itunes:setup` task, which lets you select your iTunes Library location and where on Strongspace you'd like to store it. Configuration is stored in `~/.strongspace/iTunesBackup.config` as a YAML file. With setup complete the backup will attempt to run and will print its log to your terminal.

Following a successful backup this plugin writes a hash code to `~/.strongspace/iTunesBackup.lastbackup` indicating the state of the iTunes Library the last time a successful backup was made. If you run `strongspace itunes:backup` again without using/modifying your iTunes library the plugin will let you know that `iTunes library has not changed since last backup attempt.` and exit successfully.


Scheduling
----------

The Strongspace iTunes plugin can be easily be scheduled to continuously backup your library as it changes. To set this up run.

    `strongspace itunes:schedule_backup`

This configures launchd to run the iTunes backup every minute - first checking to see if your library has changed and then performing the backup if necessary. This task stays scheduled between reboots, sleep/wake and so forth. To turn it off run `strongspace itunes:unschedule_backup`

Logs of the scheduled backup tasks can be viewed by running
    `strongspace itunes:log`


Feedback
--------

This is our first plugin and is under active development. Shoot an email to jmancuso@expandrive.com with any comments or suggestions. If you want to make an awesome fork an have us merge some great changes, we'd love that too.


