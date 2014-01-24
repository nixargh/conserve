# ahco - restore utility for Conserve backups.
#
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
#
class Disk
  puts "\tLoading Disk class..." if $debug 

  # Restore Master Boot Record
  #
  def restore_mbr(mbr, device)
    raise "MBR image #{mbr} not found." if !File.exist?(mbr)
    raise "#{device} not found isn't a block device." if !File.blockdev?(mbr)
    _, error, exit_code = runcmd("dd if=#{mbr} of=#{device} bs=512 count=1")
    raise "Failed to restore MBR: #{error}." if exit_code != 0
  end
end
