gitflow-ruby
============

A Ruby port of [Git extensions](https://github.com/nvie/gitflow "Vincent
Driessen's code") to provide high-level repository operations for Vincent
Driessen's [branching model](http://nvie.com/git-model "original blog post").

Licence terms
-------------
gitflow-ruby is published under the same terms as [nvie/gitflow](https://github.com/nvie/gitflow, see the
[LICENCE](LICENCE) file. Although the BSD Licence does not require you to share
any modifications you make to the source code, you are very much encouraged and
invited to contribute back your modifications to the community.

Any errors in gitflow-ruby are mine and not Vincent Driessen's.

Prerequisites
-------------
You will need to install git and ruby in order to run gitflow-ruby. Ruby 2.0.0
was used to develop gitflow-ruby, but it should also work with ruby 1.9.x.
See [README.orig.]() for instructions on why yiu might want to use
gitflow-ruby, and how to use it.

Installing gitflow-ruby
-----------------------
Clone this repository. Then, run the installer:

    git clone https://github.com/magister-ludi/gitflow-ruby.git
    cd gitflow-ruby
    ruby install-git-flow

You may need to run the final command with superuser privileges, e.g.

    sudo ruby install-git-flow
