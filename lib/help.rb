Strongspace::Command::Help.group('iTunes Backup') do |group|
  group.command('itunes:backup', 'Performs a backup of iTunes')
  group.command('itunes:setup', 'Create a backup profile for iTunes')
  group.command('itunes:schedule_backup', 'Schedules continuous iTunes backup')
  group.command('itunes:unschedule_backup', 'Unschedules continuous iTunes backup')
  group.command('itunes:logs', 'Opens Console.app and shows the iTunes Backup log')
end