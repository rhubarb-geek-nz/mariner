#!/bin/sh -e
#
#  Copyright 2022, Roger Brown
#
#  This file is part of rhubarb-geek-nz/mariner.
#
#  This program is free software: you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by the
#  Free Software Foundation, either version 3 of the License, or (at your
#  option) any later version.
# 
#  This program is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
#  more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>
#

VERSION=2.3.8
SYSTEM=$( . /etc/os-release ; echo "$ID/$VERSION_ID" )
RELEASE=$(git log --oneline "$0" | wc -l)

case "$SYSTEM" in
	mariner/2.* )
		RELEASE="$RELEASE.cm2"
		;;
	* )
		;;
esac

rm -rf motif*.rpm

clean()
{
	for d in *
	do
		if test -d "$d"
		then
			rm -rf "$d"
		fi
	done

	rm -rf "motif-$VERSION.tar.gz"
}

clean

trap clean 0

curl --location --silent --fail "https://sourceforge.net/projects/motif/files/Motif%20$VERSION%20Source%20Code/motif-$VERSION.tar.gz/download" --output "motif-$VERSION.tar.gz"

ACTUAL=$(sha256sum "motif-$VERSION.tar.gz" | while read A B; do echo $A; break; done)

if test "$ACTUAL" != "859b723666eeac7df018209d66045c9853b50b4218cecadb794e2359619ebce7"
then
	echo hash of gzip is wrong $ACTUAL
	rm "motif-$VERSION.tar.gz"
	false
fi

tar xfz "motif-$VERSION.tar.gz"

ls -ld "motif-$VERSION"

DESTDIR=$(pwd)/dest

LIBDIR=lib

if test -d /usr/lib64 && test ! -h /usr/lib64 
then
	cat > is64.c <<'EOF'
struct tmp {
	int a[sizeof(void *)];
	const char *p;
} tmp = {{1,2,3,4,5,6,7,8},"FIN"};
EOF

	if cc -c is64.c -Wall -Werror -o is64.o
	then
		rm is64.o
		LIBDIR=lib64
	fi

	rm is64.c
fi

(
	set -ex

	cd "motif-$VERSION"

	rpm -ql rgb
	rpm -ql rgb | grep /rgb.txt
	RGB=$( rpm -ql rgb | grep /rgb.txt )

	grep "^MWMRCDIR=" configure
	sed -i 's!^MWMRCDIR=.*$!MWMRCDIR=\"/etc/X11/mwm\"!g' configure
	grep "^MWMRCDIR=" configure

	grep "^XMBINDDIR_FALLBACK=" configure
	sed -i 's!^XMBINDDIR_FALLBACK=.*$!XMBINDDIR_FALLBACK=\"/usr/share/X11/bindings\"!g' configure
	grep ^XMBINDDIR_FALLBACK= configure

	grep "/usr/lib/X11/rgb.txt" lib/Xm/ColorS.c
	sed -i "s!/usr/lib/X11/rgb.txt!$RGB!g" lib/Xm/ColorS.c
	grep "$RGB" lib/Xm/ColorS.c

	./configure --prefix=/usr "--libdir=/usr/$LIBDIR"
	make
	make install "DESTDIR=$DESTDIR"
)

mkdir motif motif-devel

mv dest motif/dest

(
	set -e
	cd motif/dest/usr

	(
		set -e
		cd "$LIBDIR"
		rm *.la *.a
		find . -type f -name "lib*.so.*" | xargs -n1 strip
		find . -type l -name "lib*.so" | while read N
		do
			ls -ld "$N"
			SONAME=$( objdump -p "$N" | grep SONAME | while read A B
				do
					case "$A" in
						SONAME )
							echo "$B"
							;;
						* )
							;;
					esac
				done
			)
			if test -h "$SONAME"
			then
				echo CHANGE $(readlink "$N") to "$SONAME"
				ls -ld "$N"
				rm "$N"
				ln -s "$SONAME" "$N"
				ls -ld "$N"
			fi
		done
	)

	(
		set -e
		cd bin
		find . -type f | xargs -n1 strip
	)

	find share/man -type f | xargs -n1 gzip
)

mkdir -p motif/dest/usr/share/doc/motif

for d in COPYING README RELNOTES RELEASE
do
	cp "motif-$VERSION/$d" motif/dest/usr/share/doc/motif
done

mkdir -p motif-devel/dest/usr/share

rm -rf motif/dest/usr/share/Xm

mv motif/dest/usr/share/man motif-devel/dest/usr/share/man

mkdir -p motif/dest/usr/share/man/man1

mv motif-devel/dest/usr/share/man/man1/xmbind* motif-devel/dest/usr/share/man/man1/mwm* motif/dest/usr/share/man/man1

mv motif-devel/dest/usr/share/man/man4 motif/dest/usr/share/man

rm -rf motif-devel/dest/usr/share/man/manm

mv motif/dest/usr/include motif-devel/dest/usr/include

mkdir motif/dest/usr/include

mv motif-devel/dest/usr/include/X11 motif/dest/usr/include

mkdir "motif-devel/dest/usr/$LIBDIR"

mkdir "motif-devel/dest/usr/bin"

mv "motif/dest/usr/$LIBDIR/"lib*.so "motif-devel/dest/usr/$LIBDIR"

mv "motif/dest/usr/bin/uil" "motif-devel/dest/usr/bin"

cat > motif/description <<EOF
This is the Motif $VERSION run-time environment. It includes the Motif shared libraries, needed to run applications which are dynamically linked against Motif and the Motif Window Manager mwm.
EOF

cat > motif-devel/description <<EOF
This is the $VERSION development environment. It includes the header files and also static libraries necessary to build Motif applications.
EOF

echo motif - Run-time libraries and programs > motif/summary

echo motif-devel - Development libraries and header files > motif-devel/summary

while read NAME REQUIRES
do
	(
		set -e

		cd "$NAME"

		(
			SUMMARY=$(cat summary)
			echo "Name: $NAME"
			echo "Version: $VERSION"
			echo "Release: $RELEASE"
			echo "Requires: $REQUIRES"
			echo "Summary: $SUMMARY"
			echo "License: LGPLv2+"
			echo "Group: User Interface/X"
			echo "Prefix: /"
			echo
			echo "%description"
			cat description
			echo

			cat <<EOF
%files
%defattr(-,root,root)
EOF
			cd dest
			find * | while read N
			do
				if test -h "$N"
				then
					echo "/$N"
				else
					if test -d "$N"
					then
						case "$N" in
							usr | usr/bin | usr/$LIBDIR | usr/include | usr/include/X11 | usr/include/X11/bitmaps )
								;;
							etc | etc/X11 )
								;;
							usr/share | usr/share/man | usr/share/man/man* | usr/share/X11 | usr/share/doc )
								;;
							* )
								echo "%dir %attr(555,root,root) /$N"
								;;
						esac
					else
						case "$N" in
							usr/bin/* )
								echo "%attr(555,root,root) /$N"
								;;
							* )
								echo "%attr(444,root,root) /$N"
								;;
						esac
					fi
				fi
			done
		) > rpm.spec

		mkdir rpms
		PWD=$(pwd)
		
		rpmbuild --buildroot "$PWD/dest" --define "_rpmdir $PWD/rpms" --define "_build_id_links none" -bb "$PWD/rpm.spec"

		find . -name "*.rpm" -type f | while read N
		do
			mv "$N" ..
		done
		
	)
done <<EOF
motif rgb
motif-devel motif = $VERSION-$RELEASE, libXt-devel, libXext-devel
EOF
