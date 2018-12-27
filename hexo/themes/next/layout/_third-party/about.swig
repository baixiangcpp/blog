<div class="termynal-bg" onclick=onCoverBgClicked() id="termynalbg" style="display:none;" >

    <iframe class="termform" id="termynal" src="" scrolling="no" > 
    </iframe>
    
    <script>
        function onAboutClicked() {
            //document.getElementById("termynal").contentDocument.location.reload(true);
            document.getElementById("termynal").src="/about/about.html";
            document.getElementById('termynalbg').style.display="block";
        }

        function onCoverBgClicked(){
            document.getElementById('termynalbg').style.display="none";
            document.getElementById("termynal").src="";
        }

    </script>

</div>