# Conserve - linux backup tool.
# Copyright (C) 2013  nixargh <nixargh@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/gpl.html.

class LVM_operate
  attr_accessor :log, :lvm_block_size
  include Add_functions

  def initialize
    @lvm_block_size = 4 # in megabytes
    @snapshot_size_part = 80 # % from Free PE of Volume Group
    @snapshots_created = Array.new
    @duplicate_warning = false
  end

  def get_volume_group(volume)
    action = "lvdisplay -c #{volume}"
    info = do_it(action).first.split(':')
    lvm_group = info[1]
  end

  def clean!
    @snapshots_created.each do |snapshot|
      sleep 2
      info, error = delete_snapshot(snapshot)
      if info
        @log.write_noel("\t\t\tDeleting snapshot #{snapshot} - ")
        @log.write('[OK]', 'green')
        @snapshots_created.delete(snapshot)
      else
        @log.write_noel("\t\t\tCan't delete #{snapshot} snapshot: #{error}.  - ")
        @log.write('[FAILED]', 'red')
      end
    end
  end

  def create_snapshot(volume)
    begin
      status = 0
      volume = convert_to_non_mapper(volume) if volume.index("mapper")
      snapshot_name = "#{File.basename(volume)}_backup"
      snapshot = File.dirname(volume) + "\/" + snapshot_name
      if @snapshots_created.index(snapshot) && File.exist?(snapshot)
        error = nil
        @log.write_noel(' [Exist] ', 'yellow')
      else
        snapshot_size = find_space_for_snapshot(get_volume_group(volume))
        snapshot_size = snapshot_size * @shapshot_size_part / 100
        action = "lvcreate -l#{snapshot_size} -s -n #{snapshot_name} #{volume}"
        info, error = do_it(action)
        if error
          raise error
        else
          @snapshots_created.push(snapshot)
          msg = "Could not find snapshot: #{snapshot}. Maybe it's not created."
          raise msg if !File.exist?(snapshot)
        end
      end
    rescue
      status = 1
      error = $!
    end
    [status, error, snapshot]
  end

  # Delete LVM snapshot
  #
  def delete_snapshot(device)
    action = "lvremove -f #{device}"
    info, error = do_it(action)

    # next "if" is a workaround to bug, when lvm not syncing with udev and you can't remove lv by lvremove
    if error && error.index("Can't remove open logical volume")
      dev_f, lg, lv = device.split('/')
      dmdevice = "#{lg}-#{lv}"
      dmdevice-cow = "#{dmdevice}-cow"
      info, error, exit_code = runcmd("dmsetup remove #{dmdevice} && dmsetup remove #{dmdevice-cow}")
      if exit_code == 0
        info, error = do_it(action)
      end
    end

    return info, error
  end

  # Get size of device in bytes.
  #
  def get_size(device)
    action = "lvdisplay #{device}"
    info = do_it(action).first
    puts info
    size = (info.split("\n")).inject(0) do |result, line|
      line.index('Current LE') ? line.split('Current LE') : result
    end
    size.first.lstrip.to_i * @lvm_block_size * 1024 * 1024
  end

  private

  # Find space for snapshot in PE.
  #
  def find_space_for_snapshot(lvm_group)
    action = "vgdisplay -c #{lvm_group}"
    info = do_it(action).first.split(':')
    info[-2].to_i
  end

  def do_it(action)
    info, error = nil, nil
    begin
      info, error = runcmd(action)
      return [info, nil] unless error

      case error.index
      when 'give up on open_count'
        # this is to avoid SLES 11 sp.1 bug with "Unable to deact, open_count is 1" warning
        @log.write("\t\t\tBuged lvremove detected. Warnings on snapshot remove.", 'yellow')
        error = nil
      when 'Found duplicate PV'
        # this is to avoid duplication of block device with SLES11 on Hyper-V
        @log.write("\t\t\t\"duplicate PV\" SLES11 on Hyper-V problem detected. Continue backup process.", 'yellow') if !@duplicate_warning
        error = nil
        @duplicate_warning = true
      else raise error
      end
    rescue
      info = nil
      error = $!
    end
    return info, error
  end
end
