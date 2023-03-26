# Pi-Cluster Content Site

This repository contains the Jekyll configuration and content behind the [https://picluster.ricsanfre.com/](https://picluster.ricsanfre.com/) site.

## Running Locally

To view the site locally, ensure you have Ruby and Jekyll installed:

    gem install --user-install bundler jekyll

Then, in this directory, install all the required gems:

    bundle install

Finally, in this directory, run:

    bundle exec jekyll serve

Access web content through http://<host_ip>:4000

## Jekyll Theme

Embedded jekyll theme developed using as a base [aksakalli/jekyll-doc-theme](https://github.com/aksakalli/jekyll-doc-theme), and including a lot of enhancements:

- Updated versions of Bootstrap/Bootswatch (v5.1.3) and Fontawesome (v5.15.4)
- Document toc based on [allejo/jekyll-toc](https://github.com/allejo/jekyll-toc)
- Off-canvas doc navigator menu/toc for small screens (tablet/mobile)
- Search engine based on [lunr.js](https://lunrjs.com/)
- Web analytics integration with selfhosted platform [Matomo](https://matomo.org/)
- Docs comments integration with Github-discussion based comments platform,[giscus](https://giscus.app/)
