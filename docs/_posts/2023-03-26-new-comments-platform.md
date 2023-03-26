---
layout: post
title:  Website comments platform migration to giscus
date:   2023-03-26
author: ricsanfre
---


![giscus-avatar](/assets/img/giscus-app.png)

Pi-cluster Website comments platform has been migrated to  to [giscus](https://giscus.app/), a comments system powered by [GitHub Discussions](https://docs.github.com/en/discussions).

As part of the migration old comments have been lost. Sorry for the inconvenience it might cause to people who already have posted some comments.


## Migration reasons

1. Comments reply notifications by email was not working properly

   Previous comments platform based on a self-hosted remark42[remark42](https://remark42.com/) has been abandon mainly to an issue with email notifications. Users registered could assume that will receive email notifications whenever they receive a reply to their messages but this was not happening, because they needed to manually susbscribe for notifications.

   With remark42, users, using Github account or email-account,  only get email notifications about new replies to their comments (and any of the responses down the tree) if they actively subscribe for email notifications when they post a comment. See [remark42 documentation: "Email notifications to users"](https://remark42.com/docs/configuration/email/).

   In GUI the subscribe option, is not clearly explainied and highlighted its real purpose, and it seems to be an option to receive notifications from any message posted not for getting notifications to replies. Users could understand that they will receive notifications by email to their own comments without subscribing.

   ![image](https://user-images.githubusercontent.com/84853324/227768223-527e7cb5-6d66-4c37-b915-12a9d91180dc.png)

   This email notification issue is not happening with `giscus`.
   giscus automatically send email notifications when an user receive reply. User does not need to subscribe for email notifications.

2. Github Users will trust more on authorize `giscus` application to act in his behalf (Oauth authorization flow) than in my own application (`picluster`)

   To comment, visitor had to authorize `picluster` app (Oauth authorization flow), to be able to add comments. See [remark42- how to enable Github authorization](https://remark42.com/docs/configuration/authorization/#github).

   To comment, now visitors must authorize the `giscus` app to post on their behalf using the GitHub OAuth flow.

3. Giscus platform integrated with Github discussions.
 
   Alternatively, visitors can comment on the GitHub Discussion directly.
   Comments can be moderated directly on GitHub by the website administrator.

