---
publish: true
content_type: post
title: Properties
date: 2026-10-10
tags: [source/test, topics/types]
source_url: https://example.test/original
repo_url: https://github.com/example/project
zero: 0
enabled: false
absent: null
empty: ""
nothing: []
list: [false, 0, null, "", 2026-10-10, same, same]
day: 2026-10-10
instant: 2026-10-10T12:34:56Z
quoted_day: "2026-10-10"
project: "[[index#你好 世界|Home alias]]"
hidden_marker: "[[index#你好 世界|hidden-property-marker]]"
literal: "<script>{{ site.title }}</script>"
unsafe: javascript:alert(1)
credentials: https://user:pass@example.test/private
multiline: |-
  first line
  second line
long_property_name_without_any_word_boundary_to_check_wrapping: https://example.test/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
---
Body marker.
