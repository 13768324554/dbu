#!/bin/bash
# Description: generate markdown package documentation from live-build config/packages.chroot directory
# License: WTFPL
# Source: https://github.com/nodiscc/dbu
# TODO screenshots: fetch multiple screenshots
set -o errexit
set -o nounset

################################################################################

# CONFIGURATION
#fail when a package list is missing a #Cat: field
export fail_on_no_category="yes"
#language of generated package documentation
export LANG=C
#package categories to list on the main page, and to search in package lists
export package_categories="Office Multimedia Network Utility Games Development System"
#page header (markdown)
pageheader="# Installed software
See [Usage](usage.md#Installing-removing-updating-software) for documentation on installing,
removing or updating software packages.
"

################################################################################

function _genPackagesDoc {
	# gather information from a package list ($1), format it to markdown
	packagelist=$1

	packages=$(grep -E "^[a0-z9]" "$packagelist" || echo "" ) # packages in list
	mainpackage=$(echo "$packages " |head -n1 || echo "") # main package from the list
	alt_packages=$(grep -E "^#Alt:" "$packagelist" | cut -d" " -f1 --complement) # alternative/suggested packages
	md_title="# $(grep -E "^#Name" $packagelist | cut -d" " -f1 --complement)" # page title

	# remove all descriptions if the package list has a #NoDescription field
	if grep -E "^#NoDescription" "$packagelist" >/dev/null; then
		md_description=""
		md_shortdescription=""
		md_homepage=""
	# get description from the package list's #Replace field if it exists
	elif grep -E "^#Replace" "$packagelist" >/dev/null; then
		md_shortdescription=""
		md_description="$(grep -E "^#Replace" $packagelist | cut -d" " -f1 --complement)"
	# use the package list's #Desc field to specify the package to descript, if it exists, or use the first package in the list
	else
		if grep -E "^#Desc:" "$packagelist" >/dev/null; then
			descriptionpackage=$(grep -E "^#Desc" "$packagelist" | cut -d" " -f1 --complement)
		else descriptionpackage="$mainpackage"
		fi
		md_description="$(apt-cache show $descriptionpackage | grep -E "^ " | grep -Ev "::" | sed -e 's/^ \.$/ /g' | cut -b1 --complement)"
		md_shortdescription="_$(apt-cache show $descriptionpackage | grep -E "Description(-en|-fr)" | cut -d" " -f1 --complement | head -n1)_"
		md_homepage="**[Homepage]($(apt-cache show $descriptionpackage | grep -E "^Homepage:" | head -n1 | cut -d" " -f1 --complement))**"
	fi
	# use the package list's #Screenshot to specify the screenshot to fetch, or use the first package in the list
	if grep -E "^#Screenshot:" "$packagelist" >/dev/null; then
		screenshotpackages=$(grep -E "^#Screenshot:" "$packagelist" | cut -d" " -f1 --complement)
		else screenshotpackages="$mainpackage"
	fi
	md_screenshots=""
	for package in $screenshotpackages; do
		if [[ "$package" =~ ^http(s)?\:.* ]]; then
			md_screenshots="${md_screenshots}[![]($package)]($package)\n"
		else
			md_screenshots="${md_screenshots}[![](https://screenshots.debian.net/thumbnail-with-version/$package/9001)](https://screenshots.debian.net/screenshot-with-version/$package/9001)\n"
		fi
	done
	_renderMarkdown
}


function _renderMarkdown {
	echo -e "$md_title"
	if [ ! -z "$md_shortdescription" ]; then echo -e "\n_${md_shortdescription}_\n"; fi
	if [ ! -z "$md_description" ]; then
		echo -e '```'
		echo -e "\n$md_description\n"
		echo '```'
	fi
	echo -e "\n$md_screenshots\n"
	echo -e "\n$md_homepage"
	echo -e "\n### Installed packages\n"
	for i in $packages; do
		shortdescription=$(apt-cache show $i | grep -E "Description(-en|-fr)" | cut -d" " -f1 --complement | head -n1)
		pkgversion=$(apt-cache policy $i | grep -E "^  Candidate\:" | awk '{print $2}')
		echo "* [$i](https://packages.debian.org/stretch/$i) \`$pkgversion\` - $shortdescription"
	done

	echo -e "\n### Related packages\n"
	for i in $alt_packages; do
		alt_package_description=$(apt-cache show $i | grep -E "Description(-en|-fr)" | cut -d" " -f1 --complement | head -n1)
		echo " * [$i](https://packages.debian.org/stretch/$i) $alt_package_description"
	done
}

function _main {
	# check mandatory #Cat: category field
	for i in config/package-lists/[a-z]*.list.chroot; do
		if ! grep -E "#Cat:" "$i" >/dev/null; then
			echo "WARNING: No category defined for $i - list will not be included in the index page.";
			if [[ "$fail_on_no_category" = yes ]]; then exit 1; fi
		fi
	done

	# generate markdown package pages for all package lists
	for i in config/package-lists/[a-z]*.list.chroot; do
		echo "$i"
		_genPackagesDoc "$i" > "doc/packages/$(basename $i).md"
	done
}


function _gen_package_index {
	# Generate an index of all markdown package lists
	pkgindex=$(
		for category in $package_categories; do
			echo -e "\n### $category";
			for plist in config/package-lists/[a-z]*.chroot; do
					if egrep "^#Cat: $category" $plist >/dev/null; then
						pname=$(egrep "^#Name:" $plist | cut -d" " -f1 --complement)
				 		echo " - [$pname](packages/$(basename $plist).md)"
					fi
			done | sort
		done

		# Additional software from other sources
		echo -e "\n### Non-debian packages";
		find config/packages.chroot/ -name "*{all,amd64}.deb" | while read -r deb; do
			package=$(dpkg -I $deb | egrep "Package:" | awk -F' ' '{print $2}')
			homepage=$(dpkg -I $deb | egrep "Homepage:" | awk -F' ' '{print $2}')
			description=$(dpkg -I $deb | egrep "Description:" | awk '{$1=""; sub("  ", ""); print}')
			echo "* [$package]($homepage) - $description"
		done
		echo -e "\n### Firefox addons";
		echo -e "\nThese [addons for Mozilla Firefox](https://addons.mozilla.org) are part of the default installation:\n"
		grep "\[installed\]" Makefile  | sed 's/\t#/ * /'
		echo -e "\nFor a list of other interesting addons, see [this page](https://github.com/nodiscc/toolbox/blob/master/DOCS/FIREFOX-ADDONS.md)"
	)
	echo "$pageheader
	$pkgindex" > doc/packages.md
}

if [[ ! -d doc/packages/ ]]; then mkdir -p doc/packages/; fi
find doc/packages/ -name "*.md" -exec rm -v '{}' \;
_main
_gen_package_index

