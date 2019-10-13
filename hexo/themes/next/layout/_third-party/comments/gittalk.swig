{% if theme.gittalk.enable %}
    <link rel="stylesheet" href="https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog-css/gitalk.css">
    <script src="https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog-css/gitalk.min.js"></script>


    <script type="text/javascript">
        var gitalk = new Gitalk({
            clientID: 'ddb4a065ef5dbedb224e', //Client ID

            clientSecret: '0ede77323508d56231b1281291538bfd45303b20', //Client Secret

            repo: 'hexo',//仓库名称
            owner: 'baixiangcpp',//仓库拥有者
            admin: ['baixiangcpp'],
            id: location.href,      // Ensure uniqueness and length less than 50
            distractionFreeMode: false  // Facebook-like distraction free mode
        })

        gitalk.render('gitalk-container')
    </script>
{% endif %}