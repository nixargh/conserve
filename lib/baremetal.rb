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
class Baremetal
  attr_accessor :sysinfo, :destination, :exclude
  include Add_functions

  def initialize
    @jobs = Array.new
  end

  def create_jobs_list # run number of methods that creates jobs
    compile_partitions_to_mount!
    compile_mbr_backup!
    compile_boot_backup!
    compile_lvm_volumes_backup!
    compile_nonlvm_volumes_backup!
    exclude! if @exclude
    @jobs
  end

  private

  def compile_mbr_backup! # creates job to backup Master Boot Record of device with bootloader
    job = Hash.new
    job[:job_name] = "MBR backup"
    job[:source] = @sysinfo['boot']['bootloader_on']
    job[:destination] = "#{@destination}/mbr"
    job[:dest_target_type] = 'file'
    job[:mbr] = true
    job[:archive] = false 
    @jobs.push(job)
  end

  def compile_boot_backup! # creates job to backup /boot if it is separated from root
    boot_partition = @sysinfo['boot']['partition']
      if boot_partition
        job = Hash.new
        job[:job_name] = "BOOT backup"
        job[:source] = boot_partition
        #job[:destination] = "#{@destination}/boot_#{File.basename(boot_partition)}"
        job[:use_lvm] = false
        job[:archive] = true
        @jobs.push(job)
      end
  end

  def compile_lvm_volumes_backup! # creates jobs to backup LVM logical volumes that figurate at fstab
    @sysinfo['lvm'].each{|vg|
      vg['lvs'].each{|lv|
        if @partitions_to_mount.index(lv)
          job = Hash.new
          job[:job_name] = "#{lv} backup"
          job[:source] = lv
          job[:archive] = true
          @jobs.push(job)
        end
      }
    }
  end

  def compile_nonlvm_volumes_backup! # creates jobs to backup non-LVM logical volumes that figurate at fstab (exept used for /boot)
    @partitions_to_mount.each{|partition|
      if partition =~ /\/dev\/[shm]d[a-z]*[0-9]+/ && partition != @sysinfo['boot']['partition']
        job = Hash.new
        job[:job_name] = "#{partition} backup"
        job[:source] = partition
        job[:use_lvm] = false
        job[:archive] = true
        @jobs.push(job)
      end
    }
  end

  def compile_partitions_to_mount! # creates list of devices that figurates at fstab
    to_mount = Array.new
    @sysinfo['mount'].each{|device|
      dest = device['mount_info'][1]
      type = device['mount_info'][2]
      device = device['name']
      if device.index(/dev/) && type != 'swap' && !dest.index('tmp')
        to_mount.push(device)
      end
    }
    @partitions_to_mount = to_mount
  end

  def exclude! # delete jobs for excluded devices
    exclude_jobs = Array.new
    @jobs.each{|job|
      @exclude.each{|exclude|
        exclude_jobs.push(job) if job[:source] == exclude
      }
    }
    exclude_jobs.each{|job|
      @jobs.delete(job)
    }
  end
end
