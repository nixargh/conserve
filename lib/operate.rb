# This file is for options parsing.

def parse_options

# Explanation for options.
#
help = Hash.new('don\'t know')
help[:baremetal] = <<-eos
detect what to backup automatically;
\t\t\t\t\t\t\tbackups only devices from fstab;
\t\t\t\t\t\t\tyou have to point destination folder to store backup files;
\t\t\t\t\t\t\t-- collect user automatically.
eos
help[:exclude] = <<-eos
exclude devices from baremetal backup;
\t\t\t\t\t\t\tdevice name must be at "normal device name" format. For example,
\t\t\t\t\t\t\t"/dev/vg/lv". List of devices shoud be comma separated without spaces.
eos
help[:help] = <<-eos
"Conserve  Copyright (C) 2013  nixargh <nixargh@gmail.com>
This program comes with ABSOLUTELY NO WARRANTY.
This is free software, and you are welcome to redistribute it
under certain conditions.\n
Conserve v.#{$version}
- is a backup tool, which can do:
\t1. Backup block devices with LVM snapshots and dd.
\t2. Backup MBR.
\t3. Backup files from LVM snapshot or from \"live\" fs.
\t4. Backup files using rsync.
\t5. Backup to SMB or NFS share.
\t6. Collect information useful on restore.
\t7. Find out what to backup for bare metal restore.
\t8. Send report by email.\n
eos
help[:source] = <<eos
full path to block device, file or directory to backup;
\t\t\t\t\t\t\t'/dir/file, /dir, /dev/blockdev' - you can specify source as comma-separated list;
\t\t\t\t\t\t\t'/dir/*' can be used to backup all directory entries as individual sources.
eos
help[:destination] = <<-eos
full file path where to store backup;
\t\t\t\t\t\t\ttypes: smb, nfs, rsync;
\t\t\t\t\t\t\texisting file will be overwrited;
\t\t\t\t\t\t\t(in development) if source is number of files than all backup files will be added to "destination.tar" file;
\t\t\t\t\t\t\trsync: -d equals to -D;
\t\t\t\t\t\t\trsync: using / at the end of source path affects destination, use man rsync to learn more.
eos
help[:dest_dir] = <<-eos
full directory path where to store backup;
\t\t\t\t\t\t\ttypes: smb, nfs, rsync;
\t\t\t\t\t\t\tif target directory not found it will be created, but only one level;
\t\t\t\t\t\t\tbackup files names will be constructed from sources names;
\t\t\t\t\t\t\trsync: -d equals to -D;
\t\t\t\t\t\t\trsync: using / at the end of source path affects destination, use man rsync to learn more.
eos
help[:rsync_options] = 'any rsync options that you like; Default "-hru" will be overrided. "-v" can\'t be overrided.'
help[:log_enabled] = 'full path to logfile. Show info to console by default.'
help[:lvm] = 'do [not] use LVM snapshot.'
help[:plain] = 'backup files without tar as plain tree.'
help[:mount_dir] = 'root for temporary directories used to mount network shares or LVM snapshots ("/mnt" by default).'
help[:credential] = 'full path to file with smb credentials. File format as for cifs mount.'
help[:archive] = 'Archive block device image by gzip or tar and gzip files when backuping non block device.'
help[:mbr] = 'Backup MBR from device pointed like source.'
help[:collect] = <<-eos
store information about system;
\t\t\t\t\t\t\tby default path to the file will be "/destination_dir/fqdn.info".
\t\t\t\t\t\t\tif you want to save information to other file you can use it like -c="/dir".
eos
help[:inform] = <<-eos
Inform about backup status as described at config file;
\t\t\t\t\t\t\tIf no config file found it will be created.
eos
help[:job_name] = 'Set display name for backup job.'
help[:debug] = 'Show mode information about code errors.'
  # Options hash.
  #
  options = Hash.new(false)
  options[:use_lvm] = true

  # Parse options.
  #
  OptionParser.new do |params|
    params.banner = "Usage: #{$0} [options]"

    params.on('-b', '--baremetal', help[:baremetal]) do
      options[:baremetal] = true
    end

    params.on('-e', '--exclude device_1,device_2,device_n', Array,
      help[:exclude]) do |devices|
      options[:devices] = devices
    end

    params.on('--[no-]lvm', help[:lvm]) do |parameter|
      options[:use_lvm] = parameter
    end

    params.on('-z', '--gzip', help[:archive]) do
      options[:archive] = true
    end

    params.on('-l', '--log', help[:log_enabled]) do
      options[:log_enabled] = true
    end

    params.on('--[no-]mbr', help[:mbr]) do |parameter|
      options[:mbr] = parameter
    end

    params.on('-p', '--plain', help[:plain]) do
      options[:plain_files_tree] = true
    end

    params.on('-s', '--source [SOURCE]', help[:source]) do |source|
      options[:source] = source
    end

    params.on('-o', '--rsync_options opt_1,opt_2,opt_n', Array,
      help[:rsync_options]) do |opts|
      options[:rsync_options] = opts
    end

    params.on('-d', '--dest_file [FILE]', help[:destination]) do |file|
      options[:destination] = file
      options[:dest_target_type] = 'file'
    end

    params.on('-D', '--dest_dir [PATH]', help[:dest_dir]) do |dir|
      options[:destination] = dir
      options[:dest_target_type] = 'dir'
    end

    params.on('-m', '--mount_dir [PATH]', help[:mount_dir]) do |dir|
      options[:mountdir] = dir
    end

    params.on('-m', '--credential [PATH]', help[:credential]) do |path|
      options[:cred_file] = path
    end

    params.on('-c', '--collect [PATH]', help[:collect]) do |dir|
      options[:collect] = true
      options[:collect_dir] = path
    end

    params.on('-i', '--inform [PATH]', help[:inform]) do |path|
      options[:inform] = path
    end

    params.on('-n', '--job-name [NAME]', help[:job_name]) do |name|
      options[:job_name] = name
    end

    params.on('--debug', help[:debug]) do
      options[:debug] = true
      puts params
    end

    params.on_tail('-h', '--help', 'Show this message') do
      puts help[:help]
      puts params
      exit
    end

    params.on_tail('-v', '--version', 'Show version') do
      puts "Conserve - backup tool v.#{$version} (*w)."
      exit
    end
  end.parse!

  return options
end
