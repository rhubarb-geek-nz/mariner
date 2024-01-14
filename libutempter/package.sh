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

PROJECT=libutempter
VERSION=1.2.2
SYSTEM=$( . /etc/os-release ; echo "$ID/$VERSION_ID" )
RELEASE=$(git log --oneline "$0" | wc -l)

case "$SYSTEM" in
	mariner/2.* )
		RELEASE="$RELEASE.cm2"
		;;
	* )
		;;
esac

clean()
{
	for d in *
	do
		if test -d "$d"
		then
			rm -rf "$d"
		fi
	done
}

trap clean 0

DESTDIR=$(pwd)/dest

rm -rf "$DESTDIR" $PROJECT-code

git clone --single-branch --branch "$VERSION-alt1" "http://git.altlinux.org/people/ldv/packages/$PROJECT.git" "$PROJECT-code"

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
	set -e

	cd "$PROJECT-code/$PROJECT"

	HASH=$(git rev-parse HEAD)

	case "$HASH" in
		63825e2244629d44dae21132b1065d7ecc0491c0* )
			;;
		* )
			echo commit $HASH was not expected
			false
	esac

	sed -i "s!^libdir = .*!libdir = /usr/$LIBDIR!g" Makefile
	sed -i "s!^libexecdir = .*!libexecdir = /usr/libexec!g" Makefile

	make

	make install "DESTDIR=$DESTDIR"

	mkdir -p "$DESTDIR/usr/share/doc/$PROJECT" "$DESTDIR/usr/share/licenses/$PROJECT"

	cp README "$DESTDIR/usr/share/doc/$PROJECT/"
	cp COPYING "$DESTDIR/usr/share/licenses/$PROJECT/"
)

rm -rf "$PROJECT" "$PROJECT-devel" $PROJECT*.rpm

mkdir "$PROJECT" "$PROJECT-devel"

mv dest "$PROJECT/dest"

(
	cd $PROJECT/dest/usr

	find share/man -type f | xargs -n1 gzip

	for N in $(find share/man -type l)
	do
		ln -s $(readlink "$N").gz "$N".gz
		rm "$N"
	done

	find . -name "lib*.a" | while read N
	do
		if test -f "$N"
		then
			rm "$N"
		fi
	done
)

mkdir -p "$PROJECT-devel/dest/usr"

mv "$PROJECT/dest/usr/include" "$PROJECT-devel/dest/usr"

(
	cd "$PROJECT/dest"
	tar cf - usr/lib*/lib*.so usr/share/man
	rm -rf usr/lib*/lib*.so usr/share/man
) | (
	cd "$PROJECT-devel/dest"
	tar xvf -
)

cat > "$PROJECT/description" <<EOF
This library provides interface for terminal emulators such as
screen and xterm to record user sessions to utmp and wtmp files.
EOF

cat > "$PROJECT-devel/description" <<EOF
This package contains development files required to build
$PROJECT-based software.
EOF

cat > "$PROJECT/script" << 'EOF'
%pre
if getent group utmp > /dev/null
then
	:
else
	groupadd --system utmp
fi
if getent group utempter > /dev/null
then
	:
else
	groupadd --system utempter
fi
EOF

echo A privileged helper for utmp/wtmp updates > "$PROJECT/summary"

echo Development environment for $PROJECT > "$PROJECT-devel/summary"

echo System Environment/Libraries > "$PROJECT/group"

echo Development/Libraries > "$PROJECT-devel/group"

while read NAME REQUIRES
do
	(
		set -e

		cd "$NAME"

		(
			SUMMARY=$(cat summary)
			GROUP=$(cat group)
			echo "Name: $NAME"
			echo "Version: $VERSION"
			echo "Release: $RELEASE"
			echo "Requires: $REQUIRES"
			echo "Summary: $SUMMARY"
			echo "License: LGPLv2+"
			echo "Group: $GROUP"
			echo "Prefix: /"
			echo

			if test -f script
			then
				cat script
				echo
			fi

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
							usr | usr/bin | usr/lib | usr/lib64 | usr/libexec | usr/include )
								;;
							usr/share | usr/share/man | usr/share/man/man* | usr/share/doc | usr/share/licenses )
								;;
							usr/libexec/utempter )
								echo "%dir %attr(555,-,utempter) /$N"
								;;
							* )
								echo "%dir %attr(555,-,-) /$N"
								;;
						esac
					else
						case "$N" in
							usr/libexec/utempter/utempter )
								echo "%attr(2511,root,utmp) /$N"
								;;
							* )
								echo "%attr(444,root,root) /$N"
								;;
						esac
					fi
				fi
			done
		) > rpm.spec

		cat rpm.spec

		mkdir rpms
		PWD=$(pwd)
		
		rpmbuild --buildroot "$PWD/dest" --define "_rpmdir $PWD/rpms" --define "_build_id_links none" -bb "$PWD/rpm.spec"

		find . -name "*.rpm" -type f | while read N
		do
			rpm -qlvp "$N"
			mv "$N" ..
		done
		
	)
done <<EOF
$PROJECT shadow-utils
$PROJECT-devel $PROJECT = $VERSION-$RELEASE
EOF

