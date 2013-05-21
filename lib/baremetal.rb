
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
	attr_accessor :sysinfo

	def initialize
		@jobs = Hash.new
	end

	def create_jobs_list
		compile_mbr_backup!
		compile_nonlvm_volumes_backup!
		compile_lvm_volumes_backup!
	end

	def compile_mbr_backup!
		
	end
end
