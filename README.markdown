Strongspace Rsync Backup plugin
===============================

This is a plugin for the [Strongspace gem](https://github.com/expandrive/strongspace-ruby) to automatically backup any local folder to Strongspace. Currently it only works on Mac but will support windows soon enough.



Installation
------------

Upgrade/Install the Strongspace gem to v0.3.0 or newer:
    `sudo gem install strongspace`

Install the Strongspace Rsync plugin
    `strongspace plugins:install git://github.com/expandrive/strongspace-rsync.git`

Usage
-----

The following commands are added to the Strongspace command-line tool

    === Rsync Backup
    rsync:list                                    # List backup profiles
    rsync:run <name>                              # Run a backup profile
    rsync:create <name>                           # Create a backup profile
    rsync:delete <name> [remove_data]             # Delete a backup profile, [remove_data=>(yes|no)]]
    rsync:schedule <name>                         # Schedules continuous backup
    rsync:unschedule <name>                       # Unschedules continuous backup
    rsync:logs                                    # Opens Console.app and shows the Backup log
