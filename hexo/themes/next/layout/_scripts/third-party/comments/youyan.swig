 {% if not (theme.duoshuo and theme.duoshuo.shortname)
    and not theme.duoshuo_shortname
    and not theme.disqus_shortname
    and not theme.hypercomments_id
    and not theme.gentie_productKey %}

    {% if theme.youyan_uid %}
      {% set uid = theme.youyan_uid %}
    {% endif %}

   {% if page.comments %}
        <!-- UY BEGIN -->
        <script>
          var cloudTieConfig = {
            url: document.location.href, 
            sourceId: "",
            productKey: "95f8838bcab44f85b510f5f24fcb23ff",
            target: "cloud-tie-wrapper"
          };
        </script>
        <script src="https://img1.cache.netease.com/f2e/tie/yun/sdk/loader.js"></script>
        <!-- UY END -->
    {% endif %}
  {% endif %}
