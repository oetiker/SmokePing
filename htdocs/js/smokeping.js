/*++ from bonsai.js ++ urlObj  +++++++++++++++++++++++++++++++++++++++++*/
function urlObj(url) {
   var urlBaseAndParameters;

   urlBaseAndParameters = url.split("?"); 
   this.urlBase = urlBaseAndParameters[0];
   this.urlParameters = urlBaseAndParameters[1].split(/[;&]/);

   this.getUrlBase = urlObjGetUrlBase;
}

/*++ from bonsai.js ++ urlObjGetUrlBase  +++++++++++++++++++++++++++++++*/

function urlObjGetUrlBase() {
   return this.urlBase;
}

function parseRelativeTime(currTime) {
    var unit = '';
    var offset = 0;
    var sign = -1;
    var table = {
        s : 1,        // 1
        m : 60,       // s * 60
        h : 3600,     // m * 60
        d : 86400,    // h * 24
        w : 604800,    // d * 7
        mo : 2592000, // d * 30
        y : 31536000, // d * 365
    };
    var regexStr = currTime.match(/[+\-]|[^a-z]+|[a-zA-Z]+/gi);
    if (regexStr[0] == '+')
        sign = 1;
    for (i=1; i< regexStr.length; i=i+2) {
        unit = regexStr[i+1].slice(0,1);
        if (regexStr[i+1].slice(0,2) == 'mo' || (regexStr[i+1] == 'm' && Math.abs(regexStr[i]) <= 5))
            unit = 'mo';
        offset += regexStr[i]*table[unit];

    }
    offset = offset*sign;
    return Math.floor(Date.now()/1000) + offset;
}

// example with minimum dimensions
var myCropper;

var StartEpoch = 0;
var EndEpoch = 0;



function changeRRDImage(coords,dimensions){

    // disable reloading the RRD image while zoomed in
    try {
        window.stop();
    } catch (exception) {
        // fallback for IE
        document.execCommand('Stop');
    }
    
    var SelectLeft = Math.min(coords.x1,coords.x2);

    var SelectRight = Math.max(coords.x1,coords.x2);

    if (SelectLeft == SelectRight)
        return; // abort if nothing is selected.

    var RRDLeft  = 67;        // difference between left border of RRD image and content
    var RRDRight = 26;        // difference between right border of RRD image and content
    var RRDImgWidth  = $('zoom').getDimensions().width;       // Width of the Smokeping RRD Graphik
    var RRDImgUsable = RRDImgWidth - RRDRight - RRDLeft;  
    var form = $('range_form');   
    
    if (StartEpoch == 0) {
        StartEpoch = +$F('epoch_start');
        if (isNaN(StartEpoch))
            StartEpoch = parseRelativeTime($F('epoch_start'));
    }
    if (EndEpoch  == 0) {
        EndEpoch = +$F('epoch_end');
        if (isNaN(EndEpoch))
            EndEpoch = parseRelativeTime($F('epoch_end'));
    }
    var DivEpoch = EndEpoch - StartEpoch; 

    var Target = $F('target');
    var Hierarchy = $F('hierarchy');

    // construct Image URL
    var myURLObj = new urlObj(document.URL); 

    var myURL = myURLObj.getUrlBase(); 

    // Generate Selected Range in Unix Timestamps
    var LeftFactor = 1;
    var RightFactor = 1;

    if (SelectLeft < RRDLeft)
        LeftFactor = 10;        

    StartEpoch = Math.floor(StartEpoch + (SelectLeft  - RRDLeft) * DivEpoch / RRDImgUsable * LeftFactor );

    if (SelectRight > RRDImgWidth - RRDRight)
        RightFactor = 10;

    EndEpoch  =  Math.ceil(EndEpoch + (SelectRight - (RRDImgWidth - RRDRight) ) * DivEpoch / RRDImgUsable * RightFactor);


    $('zoom').src = myURL + '?displaymode=a&start=' + StartEpoch + '&end=' + EndEpoch + '&target=' + Target + '&hierarchy=' + Hierarchy;    

    myCropper.setParams();

};

if($('range_form') != null && $('range_form').length){
    $('range_form').on('submit', (function() {
        $form = $(this);

        // IMPORTANT: avoid using `$form.action` as the base URL.
        // Browsers expose it as an absolute URL even when the HTML `action`
        // attribute is relative/empty, which breaks `linkstyle=relative`.
        // Prefer the literal attribute value; if missing, treat it as empty.
        var actionAttr = $form.readAttribute('action');
        var cgiurl = ((actionAttr === null) ? '' : actionAttr).split("?");

        var action = $form.serialize().split("&");
        action = action.map(i=> i + '&');

        // Preserve the existing ordering logic, but write back a relative action
        // when the configured linkstyle resolves to relative.
        $form.writeAttribute('action', cgiurl[0] + "?" + action[4] + action[5] + action[6] + action[3]);
    }));
}

// ── Dynamic graph width ────────────────────────────────
(function () {
    var resizeTimer;
    var PADDING = 18;        // panel-body padding (8px each side) + border slack
    var MIN_WIDTH = 200;
    var MAX_WIDTH = 3000;

    function clamp(w) {
        return Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, w));
    }

    function getContentWidth() {
        var panel = document.querySelector('.main .panel-body');
        if (panel) return panel.clientWidth - PADDING;
        var main = document.querySelector('.main');
        if (main) return main.clientWidth - 40; // 20px padding each side
        return 0;
    }

    function currentUrlWidth() {
        var m = location.search.match(/[?&]width=(\d+)/);
        return m ? parseInt(m[1], 10) : 0;
    }

    function buildWidthUrl(w) {
        var url = location.href;
        if (/[?&]width=\d+/.test(url)) {
            return url.replace(/([?&]width=)\d+/, '$1' + w);
        }
        return url + (url.indexOf('?') === -1 ? '?' : '&') + 'width=' + w;
    }

    function recordWidth() {
        var w = clamp(getContentWidth());
        if (w <= 0) return;
        if (history.replaceState) {
            history.replaceState(null, '', buildWidthUrl(w));
        }
    }

    // First visit without width param: reload once so server generates
    // graphs at the correct size. On subsequent loads width is already set.
    var w = clamp(getContentWidth());
    if (w > 0 && currentUrlWidth() === 0) {
        var imgs = document.querySelectorAll('.panel-body img, .panel-body svg');
        for (var i = 0; i < imgs.length; i++) {
            imgs[i].style.display = 'none';
        }
        location.replace(buildWidthUrl(w));
    }

    // On resize: just update the URL, SVGs scale via CSS.
    // The next auto-refresh will regenerate at the correct width.
    Event.observe(window, 'resize', function () {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(recordWidth, 500);
    });
})();

Event.observe(
    window,
    'load',
    function() {
       let refresh = setTimeout(function () {
          location.reload();
       }, window.options.step * 1000);

        $('menu-button').observe('click', function (e) {
            if ($('sidebar').getStyle('left') == '0px') {
                $('body').addClassName('sidebar-hidden');
                $('body').removeClassName('sidebar-visible');
            } else {
                $('body').removeClassName('sidebar-hidden');
                $('body').addClassName('sidebar-visible');
            }
            Event.stop(e);
        });
        $('refresh-button').observe('click', function (e) {
            if (localStorage.getItem("noRefresh")) {
                localStorage.removeItem("noRefresh");
                refresh = setTimeout(function () {
                   location.reload();
                }, window.options.step * 1000);
                $('refresh-button').style.textDecoration = "line-through";
            } else {
                clearTimeout(refresh);
                localStorage.setItem("noRefresh", true);
               $('refresh-button').style.textDecoration = "none";
            }
            Event.stop(e);
        });
        if ($('zoom') != null) {
            myCropper = new Cropper.Img(
                'zoom',
                {
                    minHeight: $('zoom').getDimensions().height,
                    maxHeight: $('zoom').getDimensions().height,
                    onEndCrop: changeRRDImage
                }
            )
        }
    }
);

