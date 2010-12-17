Strongspace Rsync Backup plugin
===============================

This is a plugin for the [Strongspace gem](https://github.com/expandrive/strongspace-ruby) to automatically backup any local folder to Strongspace. Currently it only works on Mac but will support windows soon enough.

It is a trivial edit from [iTunes Plugin](https://github.com/expandrive/strongspace-itunes)


Installation
------------

Upgrade/Install the Strongspace gem to v0.0.9 or newer:
    `sudo gem install strongspace`

Install the Strongspace Rsync plugin
    `strongspace plugins:install git://github.com/minrk/strongspace-rsync.git`

See the [iTunes Plugin](https://github.com/expandrive/strongspace-itunes) for usage info, and anywhere you see 'itunes:' replace with 'rsync:'.