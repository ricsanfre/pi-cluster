# Pi-Cluster Content Site

This repository contains the Jekyll configuration and content behind the [https://picluster.ricsanfre.com/](https://picluster.ricsanfre.com/) site.

## Running Locally

To view the site locally, ensure you have Ruby and Jekyll installed:

https://jekyllrb.com/docs/installation/ubuntu/

    gem install --user-install bundler jekyll

Then, in this directory, install all the required gems:

    bundle install

Finally, in this directory, run:

    bundle exec jekyll serve

Access web content through http://<host_ip>:4000


### Error running using Ruby 3.0

During execution of `bundle exec jekyll serve` command the following error might occurs:

```shell
$ bundle exec jekyll serve
Configuration file: /home/user/Documents/blog/docs/_config.yml
            Source: /home/user/Documents/blog/docs
       Destination: /home/user/Documents/blog/docs/_site
Incremental build: disabled. Enable with --incremental
      Generating...
       Jekyll Feed: Generating feed for posts
                    done in 0.223 seconds.
jekyll 3.9.0 | Error:  no implicit conversion of Hash into Integer
/home/user/.local/share/gem/ruby/3.0.0/gems/pathutil-0.16.2/lib/pathutil.rb:502:in `read': no implicit conversion of Hash into Integer (TypeError)
        from /home/user/.local/share/gem/ruby/3.0.0/gems/pathutil-0.16.2/lib/pathutil.rb:502:in `read'
```

Jekyll 3.9 isn’t compatible with Ruby 3 so a patch need to be applied to pathutil.rb

Follow [this procedure](https://stackoverflow.com/questions/66113639/jekyll-serve-throws-no-implicit-conversion-of-hash-into-integer-error/73909796#73909796) to fix it locally:


## Jekyll Theme

Embedded jekyll theme developed using as a base [aksakalli/jekyll-doc-theme](https://github.com/aksakalli/jekyll-doc-theme), and including a lot of enhancements:

- Updated versions of Bootstrap/Bootswatch (v5.1.3) and Fontawesome (v5.15.4)
- Document toc based on [allejo/jekyll-toc](https://github.com/allejo/jekyll-toc)
- Off-canvas doc navigator menu/toc for small screens (tablet/mobile)
- Search engine based on [lunr.js](https://lunrjs.com/)
- Web analytics integration with selfhosted platform [Matomo](https://matomo.org/)
- Docs comments integration with Github-discussion based comments platform,[giscus](https://giscus.app/)
