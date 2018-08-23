{% if theme.gitment.enable %}
     {% set owner = theme.gitment.githubID %}
     {% set repo = theme.gitment.repo %}
     {% set cid = theme.gitment.ClientID %}
     {% set cs = theme.gitment.ClientSecret %}
     <link rel="stylesheet" href="http://oss.ilovecpp.com/blog-css/default.css">
     <script src="http://oss.ilovecpp.com/blog-css/gitment.browser.js"></script>
     {% if not theme.gitment.lazy %}
         <script type="text/javascript">
             var gitment = new Gitment({
                 id: '{{ page.title }}', 
                 owner: '{{owner}}',
                 repo: '{{repo}}',
                 oauth: {
                     client_id: '{{cid}}',
                     client_secret: '{{cs}}'
                 }});
             gitment.render('gitment-container');
         </script>
     {% else %}
         <script type="text/javascript">
             function ShowGitment(){
                 document.getElementById("gitment-display-button").style.display = "none";
                 document.getElementById("gitment-container").style.display = "block";
                 var gitment = new Gitment({
                     id: document.location.href, 
                     owner: '{{owner}}',
                     repo: '{{repo}}',
                     oauth: {
                         client_id: '{{cid}}',
                         client_secret: '{{cs}}',
                     }});
                 gitment.render('gitment-container');
             }
         </script>
         <div id="fuck"></div>
     {% endif %}
 {% endif %}