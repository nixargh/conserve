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
class LVM_operate
	attr_accessor :log, :lvm_block_size, :duplicate_warning, :snapshots_created
	include Add_functions
	
	def initialize
		@lvm_block_size = 4 # in megabytes
		@snapshot_size_part = 80 # % from Free PE of Volume Group
		@snapshots_created = []
		@duplicate_warning = 0
	end
	
	def get_volume_group(volume)
		action = "lvdisplay -c #{volume}"
		info = do_it(action)[0]
		lvm_group = info.split(':')[1]
	end
	
	def clean!
		@snapshots_created.each{|snapshot|
			sleep 2
#			next if !lv_exist?(snapshot) 
			info, error = delete_snapshot(snapshot)
			if info
				@log.write_noel("\t\t\tDeleting snapshot #{snapshot} - ")
				@log.write('[OK]', 'green')
#				@snapshots_created.delete(snapshot)
			else
				@log.write_noel("\t\t\tCan't delete #{snapshot} snapshot: #{error}.  - ")
				@log.write('[FAILED]', 'red')
			end
		}
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
				snapshot_size = find_space_for_snapshot(get_volume_group(volume)) * @snapshot_size_part
				snapshot_size = snapshot_size/100
				action = "lvcreate -l#{snapshot_size} -s -n #{snapshot_name} #{volume}"
				info, error = do_it(action)
				if error
					raise error
				else
					@snapshots_created.push(snapshot)
					raise "Could not find snapshot: #{snapshot}. Maybe it's not created." if !File.exist?(snapshot)
				end
			end
		rescue
			status = 1
			error = $!
		end
		result = [status, error, snapshot]
	end
	
	# convert_to_non_mapper method moved to Add_functions

	def delete_snapshot(device)
		action = "lvremove -f #{device}"
		do_it(action)
	end

	def get_size(device)
		action = "lvdisplay #{device}"
		size = nil
		info = do_it(action)[0]
		puts info
		(info.split("\n")).each{|line|
			size = line.split('Current LE')[1].lstrip! if line.index('Current LE')
		}
		size = size.to_i * @lvm_block_size * 1024 * 1024
		size # size in bytes
	end
###########
	private
###########
	def find_space_for_snapshot(lvm_group)
		action = "vgdisplay -c #{lvm_group}"
		info = do_it(action)[0]
		info = info.split(':')
		free_pe = (info[info.length - 2]).to_i # space in PE
	end
	
	def do_it(action)
		info, error = nil, nil
		begin
			info, error = runcmd(action)
#			puts
#			puts "action: #{action}"
#			puts "info: #{info}"
#			puts "error: #{error}"

			if !error
			# second part to avoid SLES 11 sp.1 bug with "Unable to deact, open_count is 1" warning
				error = nil
			elsif error.index("give up on open_count")
				# this is to avoid SLES 11 sp.1 bug with "Unable to deact, open_count is 1" warning
				@log.write("\t\t\tBuged lvremove detected. Warnings on snapshot remove.", 'yellow')
				error = nil
			elsif error.index("Found duplicate PV")
				# this is to avoid duplication of block device with SLES11 on Hyper-V
				@log.write("\t\t\t\"duplicate PV\" SLES11 on Hyper-V problem detected. Continue backup process.", 'yellow') if @duplicate_warning == 0
				error = nil
				@duplicate_warning = 1
			else
				raise error
			end
		rescue
			info = nil
			error = $!
		end
#		puts "return info: #{info}"
#		puts "return error: #{error}"
		return info, error
	end
end
