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

VERSION=1.5.2
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

	rm -rf *.tar.gz
}

clean

trap clean 0

rm -rf opensp opensp*.rpm

curl --location --silent --fail "https://sourceforge.net/projects/openjade/files/opensp/$VERSION/OpenSP-$VERSION.tar.gz/download" --output "OpenSP-$VERSION.tar.gz"

ACTUAL=$(sha256sum "OpenSP-$VERSION.tar.gz" | while read A B; do echo $A; break; done)

if test "$ACTUAL" != "57f4898498a368918b0d49c826aa434bb5b703d2c3b169beb348016ab25617ce"
then
	echo hash of gzip is wrong $ACTUAL
	rm "OpenSP-$VERSION.tar.gz"
	false
fi

tar xfz "OpenSP-$VERSION.tar.gz"

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
	set -e
	cd OpenSP-$VERSION
	for d in /usr/share/automake-*/config.guess
	do
		if test -f "$d"
		then
			rm config.guess
			ln -s "$d" config.guess
		fi
	done

	./configure  --disable-rpath --prefix=/usr "--libdir=/usr/$LIBDIR" --mandir=/usr/share/man

	make

	make install "DESTDIR=$DESTDIR"
)

mkdir -p opensp "opensp-devel/dest/usr/$LIBDIR"

mv dest opensp/dest

mv opensp/dest/usr/include opensp-devel/dest/usr

mv "opensp/dest/usr/$LIBDIR"/lib*.so "opensp-devel/dest/usr/$LIBDIR"

(
	cd opensp/dest/usr

	find . -type d -name OpenSP | while read A
	do
		B=$(dirname "$A")
		mv "$A" "$B/opensp"
	done

	(
		set -e
		cd "$LIBDIR"
		rm lib*.la lib*.a
		find . -type f -name "lib*.so.*" | xargs -n1 strip
	)

	(
		cd bin
		find . -type f | xargs -n1 strip

		while read A B
		do
			ls -ld "$A"
			ln -s "$A" "$B"
			ls -ld "$B"
		done << EOF
onsgmls nsgmls
osx sgml2xml
ospam spam
ospent spent
osgmlnorm sgmlnorm
EOF
	)

	find share/man -type f | xargs -n1 gzip
)

cat > opensp/description <<'EOF'
OpenSP is an implementation of the ISO/IEC 8879:1986 standard SGML
(Standard Generalized Markup Language). OpenSP is based on James
Clark's SP implementation of SGML. OpenSP is a command-line
application and a set of components, including a generic API.
EOF

echo opensp - SGML and XML parser > opensp/summary

cat > opensp-devel/description <<'EOF'
Header files and libtool library for developing applications that use OpenSP.
EOF

echo opensp-devel - Files for developing applications that use OpenSP > opensp-devel/summary

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
			echo "License: MIT"
			echo "Group: Applications/Text"
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
							usr | usr/bin | usr/$LIBDIR | usr/include )
								;;
							usr/share | usr/share/man* | usr/share/doc )
								;;
							usr/share/locale* )
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
			rpm -qlvp "$N"
			mv "$N" ..
		done
		
	)
done <<EOF
opensp sgml-common
opensp-devel opensp = $VERSION-$RELEASE
EOF
