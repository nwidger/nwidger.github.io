---
title: "Making a reveal.js presentation with org-reveal"
description: "Using org-reveal to make reveal.js presentations"
date: "2013-12-19"
categories: ["emacs"]
---

I'm currently working on putting together the presentation for my
thesis defense and like all other things I wanted to put it together
inside Emacs.  I had heard of
[reveal.js](https://github.com/hakimel/reveal.js/) and wanted to give
it a shot for a while, and fortunately someone made
[org-reveal](https://github.com/yjwen/org-reveal) which allows
exporting an [org-mode](http://orgmode.org) file to a reveal.js
presentation.  Here's how I put together my presentation.

## Create your presentation directory

First make a directory to hold your presentation file:

    mkdir presentation
	cd presentation

create a directory inside to hold any images you may use:

	mkdir images

create a `presentation.css` file to store any custom CSS rules you may
need:

    touch presentation.css

## Install org-reveal

Obviously, `org-reveal` requires `org`.  `org` ships with Emacs by
default, but I install it out of [MELPA](http://melpa.milkbox.net/#/)
to ensure I'm running the latest version.  To install `org` and
`org-reveal`, first add MELPA to your package repositories in your
Emacs init file:

    (package-initialize)
    
    (add-to-list 'package-archives
    	     '("melpa" . "http://melpa.milkbox.net/packages/") t)

Evaluate that code with `eval-region` or just restart Emacs.  Make
sure your package list is up to date by running `M-x
package-refresh-contents`, then run `M-x package-install org RET` and
then `M-x package-install ox-reveal RET` to install both packages.

I added the following to my Emacs init file to ensure they both get
loaded on startup (add this *after* the call to `package-initialize`):

    (require 'org)
    (require 'ox-reveal)

## Install reveal.js

Next download the latest
[reveal.js release](https://github.com/hakimel/reveal.js/releases)
tarball and extract it to the `presentation` directory.  Rename the
resulting directory to `reveal.js`:

    wget https://github.com/hakimel/reveal.js/archive/2.6.1.tar.gz
	tar xfz 2.6.1.tar.gz
	mv reveal.js-2.6.1 reveal.js

Go into the `reveal.js` directory and use `npm` to download the
necessary dependencies (`reveal.js` requires
[Node.js](http://nodejs.org/) and
[Grunt](http://gruntjs.com/getting-started#installing-the-cli)):

    cd reveal.js
    sudo npm install

follow the
[reveal.js install instructions](https://github.com/hakimel/reveal.js/#installation)
if you run into any problems here.

## Create presentation file

Create a `presentation.org` file and add the following header to the
top:

    #    -*- mode: org -*-
    #+OPTIONS: reveal_center:t reveal_progress:t reveal_history:t reveal_control:t
    #+OPTIONS: reveal_mathjax:t reveal_rolling_links:t reveal_keyboard:t reveal_overview:t num:nil
    #+OPTIONS: reveal_width:1200 reveal_height:800
    #+OPTIONS: toc:1
    #+REVEAL_MARGIN: 0.2
    #+REVEAL_MIN_SCALE: 0.5
    #+REVEAL_MAX_SCALE: 2.5
    #+REVEAL_TRANS: none
    #+REVEAL_THEME: night
    #+REVEAL_HLEVEL: 999
    #+REVEAL_EXTRA_CSS: ./presentation.css

    #+TITLE: My Title Goes Here
    #+AUTHOR: Your Name Goes Here
    #+EMAIL: your.email@goes.here

You will probably want to play around with `REVEAL_THEME` (choices
[here](https://github.com/hakimel/reveal.js/#theming)), `REVEAL_TRANS`
(the slide transition effect, must be one of `default`, `cube`,
`page`, `concave`, `zoom`, `linear`, `fade` or `none`) and
`REVEAL_HLEVEL`.  I set `REVEAL_HLEVEL` to 999 so that all slides are
horizontal, see [here](https://github.com/yjwen/org-reveal#the-hlevel)
for details.  Note the `REVEAL_EXTRA_CSS` option which pulls in any
extra CSS rules you've added to your `presentation.css` file.

Now you can start creating your presentation.  Each heading
corresponds to a new slide.

### Images

Images can be inserted into your presentation like so:

    [[./images/myimage.png]]

you can use put `#+ATTR_HTML :attr1 attr1_value, :attr2 attr2_value`
above the image link to add custom HTML attributes, like so:

    #+ATTR_HTML: :height 200%, :width 200%
    [[./images/myimage.png]]

### Tables

`org` tables are also exported properly, although I found they look
better when stretched to fill the screen:

    #+ATTR_HTML: :width 100%
	| column_title1  | column_title2 |
	|----------------+---------------|
	| a              | b             |
    | a              | b             |
	| a              | b             |

I also added a few custom rules to `presentation.css` to center the
table text and put a border around the cells:

    .reveal table th, .reveal table td {
        text-align: center;
        border: 1px solid white;
    }

### Code Fragments

You can insert source code between `#+BEGIN_SRC` and `#+END_SRC`.  If
you specify the language you get awesome syntax highlighting for free
thanks to `org-babel`:

    #+BEGIN_SRC java
    class MyClass extends Object {
	
	}
    #+END_SRC

I found that the code blocks weren't displaying correctly due to the
`pre` blocks being set to `width: 90%`.  I fixed this by adding the
following rule to my `presentation.css` file:

    .reveal pre {
        width: 100%;
        border: none;
        box-shadow: none;
    }

### Speaker's notes

You can add speaker's notes to each slide between `#+BEGIN_NOTES` and
`#+END_NOTES`.  While viewing your presentation, press `s` to pull up
the speaker's window to see your notes.

## Generate the presentation

Generate your presentation by running `C-c C-e R R`.  Once it's
finished, there should be a new `presentation.html` file.  Just open
it in your browser to view your presentation!  Press `f` to go
fullscreen or `Esc` to see the slide overview.


