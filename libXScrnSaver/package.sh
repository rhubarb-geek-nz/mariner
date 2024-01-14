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

PROJECT=libXScrnSaver
VERSION=1.2.3
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

trap clean 0

curl --location --silent --fail "https://www.x.org/releases/individual/lib/$PROJECT-$VERSION.tar.gz" -o "$PROJECT-$VERSION.tar.gz"

ACTUAL=$(sha256sum "$PROJECT-$VERSION.tar.gz" | while read A B; do echo $A; break; done)

if test "$ACTUAL" != "4f74e7e412144591d8e0616db27f433cfc9f45aae6669c6c4bb03e6bf9be809a"
then
	echo hash of gzip is wrong $ACTUAL
	rm "$PROJECT-$VERSION.tar.gz"
	false
fi

curl --location --silent --fail "https://www.x.org/releases/individual/proto/scrnsaverproto-1.2.2.tar.gz" -o "scrnsaverproto-1.2.2.tar.gz"

ACTUAL=$(sha256sum "scrnsaverproto-1.2.2.tar.gz" | while read A B; do echo $A; break; done)

if test "$ACTUAL" != "d8dee19c52977f65af08fad6aa237bacee11bc5a33e1b9b064e8ac1fd99d6e79"
then
	echo hash of gzip is wrong $ACTUAL
	rm "scrnsaverproto-1.2.2.tar.gz"
	false
fi

DESTDIR=$(pwd)/dest

rm -rf "$DESTDIR" "$DESTDIR-devel"

tar xfz "$PROJECT-$VERSION.tar.gz"

tar xfz scrnsaverproto-1.2.2.tar.gz

(
	set -e

	cd scrnsaverproto-1.2.2

	for d in /usr/share/automake*/config.guess
	do
		if test -f "$d"
		then
			rm -rf config.guess
			ln -s "$d" config.guess
			break
		fi
	done

	./configure --prefix=/usr

	make

	make install DESTDIR="$DESTDIR-devel"

	rm -rf "$DESTDIR-devel/usr/include/X11/extensions"/saver*.h
)

(
	set -e

	cd $PROJECT-$VERSION

	for d in /usr/share/automake*/config.guess
	do
		if test -f "$d"
		then
			rm -rf config.guess
			ln -s "$d" config.guess
			break
		fi
	done

	./configure --prefix=/usr CPPFLAGS="-I$DESTDIR-devel/usr/include"

	make

	make install DESTDIR="$DESTDIR"

	for d in COPYING ChangeLog README
	do
		if test -s "$d"
		then
			mkdir -p "$DESTDIR/usr/share/doc/$PROJECT" 
			cp "$d" "$DESTDIR/usr/share/doc/$PROJECT"
		fi
	done
)

rm -rf "$PROJECT" "$PROJECT-devel" $PROJECT*.rpm

mkdir "$PROJECT" "$PROJECT-devel"

mv dest "$PROJECT/dest"
mv dest-devel "$PROJECT-devel/dest"

rm -rf "$PROJECT-devel/dest/usr/lib/pkgconfig"

mv "$PROJECT/dest/usr/lib/pkgconfig" "$PROJECT-devel/dest/usr/lib"

(
	cd "$PROJECT/dest"

	(
		cd usr/lib
		rm -rf lib*.la lib*.a
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
)

mv "$PROJECT/dest/usr/lib/"lib*.so "$PROJECT-devel/dest/usr/lib"

mkdir -p "$PROJECT-devel/dest/usr/share"

mv "$PROJECT/dest/usr/share/man" "$PROJECT-devel/dest/usr/share"

find "$PROJECT-devel/dest/usr/share/man/man3" -type f | sort | while read N
do
	HEAD=$(head -1 "$N")
	case "$HEAD" in
		".so man3/Xss.3" )
			ln -s Xss.3.gz "$N.gz"
			rm "$N"
			;;
		* )
			;;
	esac	
done

find "$PROJECT-devel/dest/usr/share/man" -type f | xargs -n1 gzip

rm -rf "$PROJECT-devel/dest/usr/share/doc/scrnsaverproto"

cat > "$PROJECT/description" <<EOF
X.Org X11 libXss runtime library
EOF

cat > "$PROJECT-devel/description" <<EOF
X.Org X11 libXss development package
EOF

echo X.Org X11 libXss runtime library > "$PROJECT/summary"

echo X.Org X11 $PROJECT development package > "$PROJECT-devel/summary"

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
			if test -n "$REQUIRES"
			then
				echo "Requires: $REQUIRES"
			fi
			echo "Summary: $SUMMARY"
			echo "License: MIT"
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
							usr | usr/bin | usr/lib* | usr/include* )
								;;
							usr/share | usr/share/man* | usr/share/doc | usr/share/licenses )
								;;
							* )
								echo "%dir %attr(555,-,-) /$N"
								;;
						esac
					else
						case "$N" in
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
$PROJECT
$PROJECT-devel $PROJECT = $VERSION-$RELEASE, libX11-devel
EOF
