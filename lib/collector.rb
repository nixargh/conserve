#Conserve - linux backup tool.
#Copyright (C) 2013  nixargh <nixargh@gmail.com>
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see http://www.gnu.org/licenses/gpl.html.
class Collector
  include Add_functions

  def initialize
    @creatures = Hash.new []
  end

  def collect # collect iformation about creatures
    list_disks!
#   @creatures.sort.each { |creature, value|
#     @creatures[creature] = eval("get_#{creature}_info")
#   }
    @creatures['hdd'] = get_hdd_info
    @creatures['md'] = get_md_info
    @creatures['dmraid'] = get_dmraid_info
    @creatures['partition'] = get_partition_info
    @creatures['lvm'] = get_lvm_info
    @creatures['mount'] = get_mount_info
    @creatures['boot'] = get_boot_info
    @creatures
  end

  private

  def get_hdd_info # collect information about phisical disk devices
    hdd_list = Array.new
    @disk_list.each { |disk, size|
      if disk =~ /\A\/dev\/[hs]d[a-z]{1,2}\z/
        hdd = Hash.new
        hdd['name'] = disk
        hdd['size'] = size
        hdd['blocksize'] = get_device_blocksize(disk)
        hdd['uuid'], hdd['type'], hdd['label'] = get_uuid_type_label(disk)
        hdd['has_grub_mbr'] = find_grub_mbr(disk)
        #hdd['label'] = get_label(disk)
        hdd_list.push(hdd)
      end
    }
    hdd_list
  end

  def get_md_info # collect information about Linux RAID devices
    md_list = Array.new
    @disk_list.each { |disk, size|
      if disk =~ /\A\/dev\/md\d{1,3}\z/
        raid = Hash.new
        raid['name'] = disk
        `cat /proc/mdstat`.each_line { |line|
          if line.index(File.basename(disk))
            line.scan(/raid\d{1,2}/) { |raid_lvl|
              raid['raid_lvl'] = raid_lvl.match(/\d{1,2}/)[0].to_i
            }
            raid['members'] = Array.new
            line.scan(/[hs]d[a-z]{1,2}\d/) { |disk|
              raid['members'].push("/dev/#{disk}")
            }
          end
        }
        raid['uuid'], raid['type'], raid['label'] = get_uuid_type_label(disk)
        #raid['label'] = get_label(raid['name'])
        raid['has_grub_mbr'] = find_grub_mbr(raid['name'])
        md_list.push(raid)
      end
    }
    md_list
  end

  def get_dmraid_info # collect information about software RAID devices
    dm_raids = Array.new
      info, error = runcmd("dmraid -s -c -c -c")
      if info
        if info != 'no raid disks'
          info.each_line { |line|
            line = line.split(':')
            if !line[0].index('/')
              raid = Hash.new
              raid['name'] = get_dmraid_fullname(line[0])
              raid['raid_lvl'] = raid_lvl_to_number(line[3])
              raid['devices'] = Array.new
              raid['size'] = get_device_size(raid['name'])
              raid['has_grub_mbr'] = find_grub_mbr(raid['name'])
              dm_raids.push(raid)
            else
              dm_raids.last['devices'].push(line[0])
            end
          }
        end
      end
    dm_raids
  end

  def get_partition_info # collect information about partition tables
    partition_list = Array.new
    disks = Array.new
    disks = @creatures['hdd'] + @creatures['dmraid']
    disks.each { |hdd|
      if hdd['type'] == nil
        partitions = Hash.new
        partitions['disk'] = hdd['name']
        partitions['partitions'] = read_partitions(hdd['name'])
        partitions['partitions'].each { |partition|
          partition['uuid'], partition['type'], partition['label'] = get_uuid_type_label(partition['name'])
          partition['has_grub_mbr'] = find_grub_mbr(partition['name'])
          #partition['label'] = get_label(partition['name'])
        }
        partition_list.push(partitions)
      end
    }
    partition_list
  end

  def get_lvm_info # collect information about LVM
    begin
      vg_list = Array.new
      backup_dir = "/tmp/vgcfgbackup"
      backup_files = Array.new
      Dir.mkdir(backup_dir) if !File.directory?(backup_dir)
      info, error = runcmd("vgcfgbackup -f #{backup_dir}/%s")
      dir = Dir.open(backup_dir)
      raise "Can't collect LVM info: #{error}." if error
      dir.each { |file|
        if file != '.' && file !='..'
          vg = Hash.new
          vg['name'] = file
          vg['lvs'] = get_vg_lvs(file)
          backup_file = "#{backup_dir}/#{file}"
          backup_files.push(backup_file)
          vg['config'] = IO.read(backup_file)
          vg_list.push(vg)
        end
      }
      vg_list
    ensure
      backup_files.each { |file|
        File.unlink(file) if File.exist?(file)
      }
      Dir.unlink(backup_dir) if File.directory?(backup_dir)
    end
  end

  def get_vg_lvs(vg) # find logical volumes of LVM volume group
    lvs = Array.new
    info, error = runcmd("lvdisplay -c #{vg}")
    if !error
      info.each_line { |line|
        line.strip!
        lv = line.split(':')[0]
        lvs.push(lv)
      }
    else
      raise "can't find lv for vg=\"#{vg}\": #{error}."
    end
    lvs
  end

  def get_mount_info # collect information about how to mount partitions
    mounts = Array.new
    IO.read('/etc/fstab').each_line { |line|
      line.chomp!.strip!
      if !line.empty? && line.index('#') != 0
        device = Hash.new
        device['mount_info'] = line.split(' ')
        device_name = device['mount_info'][0]
        device['name'] = to_ndn(device_name)
        mounts.push(device)
      end
    }
    mounts
  end

  def get_boot_info # find where GRUB installed (ignore partitions)
    bootloader = Hash.new
    boot_folder_hdd = find_where_boot_folder
    hdd_and_md = @creatures['hdd'] + @creatures['md'] + @creatures['dmraid']
    hdd_and_md.each { |hdd|
      if hdd['has_grub_mbr']
        if hdd['name'] == boot_folder_hdd
          bootloader['bootloader_on'] = hdd['name']
          bootloader['bootloader_type'] = File.exist?('/boot/grub/menu.lst') ? 'grub' : 'grub2'
          bootloader['partition'] = find_boot_partition
        end
      end
    }
    if bootloader.empty?
      @creatures['partition'].each { |hdd|
        hdd['partitions'].each { |partition|
          if partition['has_grub_mbr']
            if partition['name'] == find_boot_partition
              bootloader['bootloader_on'] = partition['name']
              bootloader['bootloader_type'] = File.exist?('/boot/grub/menu.lst') ? 'grub' : 'grub2'
              bootloader['partition'] = partition['name']
            end
          end
        }
      }
    end
    bootloader
  end

  def find_boot_partition # detect if boot partition separated from root or return nil
    @creatures['mount'].each { |device|
      line = device['mount_info']
      if line[1] == '/boot'
        partition = line[0]
        return to_ndn(partition)
      end
    }
    nil
  end

  def find_where_boot_folder # detect on which device "/boot" folder is
    boot, root = nil, nil
    @creatures['mount'].each { |device|
      line = device['mount_info']
      boot = line[0] if line[1] == '/boot'
      root = line[0] if line[1] == '/'
    }
    device = boot ? boot : root
    device = to_ndn(device)
    device =~ /\/dev\/md[0-9]/ ? device : find_partitions_disk?(device)
  end

  def to_ndn(device) # convert different device path to "normal device name". exp: /dev/data/test or /dev/sda2
    return nil unless device
    if device.upcase.index('UUID')
      uuid = device.split('=')[1]
      device = find_by_uuid(uuid)
      raise "Can't resolv UUID #{uuid} to \"normal device name\"." unless device
    elsif device.index('/mapper/')
      device = convert_to_non_mapper(device)
      raise "Can't resolv mapper name #{device} to \"normal device name\"." unless device
    elsif device.upcase.index('LABEL')
      label = device.split('=')[1]
      device = find_by_label(label)
      raise "Can't resolv label #{label} to \"normal device name\"." unless device
    end
    device
  end

  # Finds what hdd this partition belongs to.
  #
  def find_partitions_disk?(device)
    @creatures['partition'].each do |group|
      group['partitions'].each do |partition|
        return group['disk'] if partition['name'] == device
      end
    end
    nil
  end

  def find_by_uuid(uuid)
    find_by_attribute('uuid', uuid)
  end

  def find_by_label(label)
    find_by_attribute('label', label)
  end

  # Find device by its' attributes' name and type.
  #
  def find_by_attribute(type, attribute)
    name = find_attribute(@creatures['hdd'], type, attribute)
    name = find_attribute(@creatures['md'], type, attribute) unless name
    @creatures['partition'].each do |hdd|
      return name if name
      name = find_attribute(hdd['partitions'], type, attribute)
    end
    name
  end

  # Find attribute in hash.
  # Params:
  #   @array - array of hashes, each hash has field 'name';
  #   @type - type of attribute, each hash also has this field;
  #   @name - name of attribute.
  #
  def find_attribute(array, type, name)
    array.each do |hash|
      return hash['name'] if name == hash[type]
    end
    nil
  end

  def find_grub_mbr(device) # detect if there is GRUB's info at hdd mbr
    info, error = runcmd("dd bs=512 count=1 if=#{device} 2>/dev/null")
    if info
      info.index('GRUB') ? true : false
    else
      false
    end
  end

  # Create list with sizes of different disk devices on current machine.
  # Correct string for parsing looks like this:
  # Disk /dev/sda: 320.1 GB, 320072933376 bytes, 625142448 sectors
  #
  def list_disks!
    @disk_list = Hash.new
    `fdisk -l 2>/dev/null`.each_line do |line|
      next unless line.index('Disk /')
      dev, size = line.split(':')
      dev = dev.split(' ').last    # device name
      # Bug I guess. String in comments says that it's size in sectors.
      size = size.split(' ')[-2]    # size in bytes
      @disk_list[dev] = size.to_i
    end
  end

  def get_device_size(dev) # size in bytes
    `blockdev --getsize64 #{dev}`.chomp.to_i
  end

  def get_device_blocksize(dev) # get blocksize of device in bytes
    `blockdev --getbsz #{dev}`.chomp.to_i
  end

  def get_uuid_type_label(device) # get uuid and type and label of block device
    uuid, type, label = nil, nil, nil
    info = `blkid #{device}`.split(' ')
    info.map { |x| x.split('=').last.delete('"') }.each do |arg|
      uuid = arg if arg.index('UUID')
      type = arg if arg.index('TYPE')
      label = arg if arg.index('LABEL')
    end
    return uuid, type, label
  end

  def read_partitions(disk) # read partitions table of disk + some of partition attributes
    info, error = runcmd("sfdisk -l #{disk} -d -x")
    error = read_partitions_error_handling if error
    raise "Error while reading partitions table of #{disk}: #{error}." if error
    info.each_line.inject[] do |partitions, line|
      partition = read_partition(line)
      partition ? partitions << partition : partitions
    end
  end

  def read_partitions_error_handling(error)
    error.chomp!
    if error.index('GPT')
      # stub. need to write alternative detection method for GPT partition table
      raise "GPT partition table detected on #{disk}. Don't know how to work with it."
    elsif error == "Warning: extended partition does not start at a cylinder boundary.\nDOS and Linux will interpret the contents differently."
      # stub for that warning
      error = nil
    end
    error
  end

  # Parse information about partition given string with information itself.
  # Correct string looks like this:
  # /dev/sda2 : start=   819315, size=  5253255, Id=82
  #
  def read_partition(line)
    return nil unless line.index('/dev/') == 0
    partition = Hash.new
    partition['name'], properties = line.split(' : ')
    _, partition['size'], partition['id'] = properties.split(',').
      map { |x| x.split('=').last.to_i }
    partition['size'] > 0 ? partition : nil
  end

  def get_label(device) # gets device label
    info, error = runcmd("e2label #{device}")
    return info if info && !info.empty? && !error
    nil
  end

  def raid_lvl_to_number(raid_lvl_string) # convert string raid level to raid level number
    case raid_lvl_string
    when 'stripe' then 0
    when 'mirror' then 1
    when 'stripe on top of mirrors' then 10
    when 'mirror on top of stripes' then 01 # here's a bug, 01 == 1.
    else raise "Unknown software raid type: \"#{raid_lvl_string}\"."
    end
  end

  def get_dmraid_fullname(dmraid) # resolv dmraid device name to full path
    require 'find'
    Find.find('/dev') do |path|
      return path if !File.directory?(path) && File.basename(path) == dmraid
    end
    nil
  end
end
