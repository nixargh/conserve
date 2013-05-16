conserve
========

Conserve - is a linux backup utility.

Conserve is designed to use LVM snapshots and 'dd' to create images of partitions. But it can backup files and non-LVM partitions too.
It is writed on ruby. 

Conserve can do:
1. Backup block devices with LVM snapshots and dd.
2. Backup MBR.
3. Backup files from LVM snapshot or from \"live\" fs.
4. Backup to smb share.
5. Collect information useful on restore.
6. Send report by email.

More information can be found here - http://conserve.magic-beans.org/
