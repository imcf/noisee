Building the NoiSee package
===========================

The package is based on the [example-script-collection][gh_example-script] which
is using [Maven][www_mvn] as the build system. To build the package, simply run
`mvn` on the command line or launch the helper script that optionally takes the
path to your *Fiji* location as a parameter, using it to tell maven where to
deploy the resulting package (defaulting to `/opt/Fiji.app/`):

```
bash scripts/build_and_deploy.sh </path/to/your/Fiji.app/>
```

Making a new release
====================

To create a new release, clone the [scijava-scripts][gh_scijava-scripts] repo
(e.g. in `/opt/imagej/`) and run the `release-version.sh` helper:

```
BASE_DIR=/opt/imagej
mkdir -pv "$BASE_DIR"
cd "$BASE_DIR"
git clone https://github.com/scijava/scijava-scripts
cd -

"$BASE_DIR/scijava-scripts/release-version.sh" --skip-push --skip-gpg
```

[gh_example-script]: https://github.com/imagej/example-script-collection
[www_mvn]: https://maven.apache.org
[gh_scijava-scripts]: https://github.com/scijava/scijava-scripts
