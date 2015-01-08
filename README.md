Flattened BOSH repo
===================

For the https://github.com/cloudfoundry-community/traveling-bosh project we currently need patches to various BOSH & downstream gems. We can do this via a Gemfile. But when we package up traveling-bosh it will include the entire BOSH git repository, which inflated the downloadable package from 60M to 1G.

This repository is the smallest version of BOSH repo that contains the patched parts of BOSH.

It can be recreated using the `rake rebuild`, which will recreate a new git repo.
