/*++ from bonsai.js ++ urlObj  +++++++++++++++++++++++++++++++++++++++++*/
function urlObj(url) {
   var urlBaseAndParameters;

   urlBaseAndParameters = url.split("?");
   this.urlBase = urlBaseAndParameters[0];
   this.urlParameters = (urlBaseAndParameters[1] || '').split(/[;&]/);

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
    if (!regexStr) return Math.floor(Date.now() / 1000);
    if (regexStr[0] == '+')
        sign = 1;
    for (var i = 1; i < regexStr.length; i = i + 2) {
        if (i + 1 >= regexStr.length) break;
        unit = regexStr[i+1].slice(0,1);
        if (regexStr[i+1].slice(0,2) == 'mo' || (regexStr[i+1] == 'm' && Math.abs(regexStr[i]) <= 5))
            unit = 'mo';
        offset += regexStr[i]*table[unit];

    }
    offset = offset*sign;
    return Math.floor(Date.now()/1000) + offset;
}

/* ++ Crop Selection Handler ++ */

var cropSelection = null;

function initCropper(imgEl, onEndCrop) {
    var wrap = document.createElement('div');
    wrap.className = 'sp-crop-wrap';
    wrap.style.position = 'relative';
    wrap.style.display = 'inline-block';
    wrap.style.cursor = 'crosshair';
    wrap.style.userSelect = 'none';
    imgEl.parentNode.insertBefore(wrap, imgEl);
    wrap.appendChild(imgEl);

    var overlay = document.createElement('div');
    overlay.className = 'sp-crop-overlay';
    overlay.style.cssText = 'position:absolute;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.3);pointer-events:none;display:none;';
    wrap.appendChild(overlay);

    var sel = document.createElement('div');
    sel.className = 'sp-crop-selection';
    sel.style.cssText = 'position:absolute;top:0;height:100%;background:rgba(255,255,255,0.2);border-left:1px dashed #fff;border-right:1px dashed #fff;pointer-events:none;display:none;z-index:2;';
    wrap.appendChild(sel);

    var dragging = false;
    var startX = 0;

    wrap.addEventListener('pointerdown', function(e) {
        if (e.button !== 0) return;
        dragging = true;
        var rect = wrap.getBoundingClientRect();
        startX = e.clientX - rect.left;
        sel.style.left = startX + 'px';
        sel.style.width = '0px';
        sel.style.display = 'block';
        overlay.style.display = 'block';
        wrap.setPointerCapture(e.pointerId);
        e.preventDefault();
    });

    wrap.addEventListener('pointermove', function(e) {
        if (!dragging) return;
        var rect = wrap.getBoundingClientRect();
        var curX = e.clientX - rect.left;
        var left = Math.min(startX, curX);
        var width = Math.abs(curX - startX);
        sel.style.left = left + 'px';
        sel.style.width = width + 'px';
    });

    wrap.addEventListener('pointerup', function(e) {
        if (!dragging) return;
        dragging = false;
        var rect = wrap.getBoundingClientRect();
        var endX = e.clientX - rect.left;
        sel.style.display = 'none';
        overlay.style.display = 'none';
        if (onEndCrop) {
            onEndCrop(
                { x1: Math.min(startX, endX), x2: Math.max(startX, endX) },
                { width: rect.width, height: rect.height }
            );
        }
    });

    wrap.addEventListener('pointercancel', function() {
        dragging = false;
        sel.style.display = 'none';
        overlay.style.display = 'none';
    });

    return {
        setParams: function() {
            sel.style.display = 'none';
            overlay.style.display = 'none';
        }
    };
}

/* ++ Zoom / Graph Update ++ */

var myCropper;
var StartEpoch = 0;
var EndEpoch = 0;

function changeRRDImage(coords, dimensions) {

    // disable reloading the RRD image while zoomed in
    window.stop();

    var SelectLeft = Math.min(coords.x1, coords.x2);
    var SelectRight = Math.max(coords.x1, coords.x2);
    SelectLeft = Math.max(0, SelectLeft);
    SelectRight = Math.min(dimensions.width, SelectRight);

    if (SelectLeft == SelectRight)
        return; // abort if nothing is selected.

    var RRDLeft  = 67;        // difference between left border of RRD image and content
    var RRDRight = 26;        // difference between right border of RRD image and content
    var zoomEl = document.getElementById('zoom');
    var RRDImgWidth  = zoomEl.getBoundingClientRect().width;
    var RRDImgUsable = RRDImgWidth - RRDRight - RRDLeft;

    if (StartEpoch == 0) {
        StartEpoch = +document.getElementById('epoch_start').value;
        if (isNaN(StartEpoch))
            StartEpoch = parseRelativeTime(document.getElementById('epoch_start').value);
    }
    if (EndEpoch  == 0) {
        EndEpoch = +document.getElementById('epoch_end').value;
        if (isNaN(EndEpoch))
            EndEpoch = parseRelativeTime(document.getElementById('epoch_end').value);
    }
    var DivEpoch = EndEpoch - StartEpoch;

    var Target = document.getElementById('target').value;
    var Hierarchy = document.getElementById('hierarchy').value;

    // construct Image URL
    var myURLObj = new urlObj(document.URL);
    var myURL = myURLObj.getUrlBase();

    // Generate Selected Range in Unix Timestamps
    var LeftFactor = 1;
    var RightFactor = 1;

    if (SelectLeft < RRDLeft)
        LeftFactor = 10;

    StartEpoch = Math.floor(StartEpoch + (SelectLeft  - RRDLeft) * DivEpoch / RRDImgUsable * LeftFactor);

    if (SelectRight > RRDImgWidth - RRDRight)
        RightFactor = 10;

    EndEpoch = Math.ceil(EndEpoch + (SelectRight - (RRDImgWidth - RRDRight)) * DivEpoch / RRDImgUsable * RightFactor);

    zoomEl.src = myURL + '?displaymode=a&start=' + StartEpoch + '&end=' + EndEpoch + '&target=' + encodeURIComponent(Target) + '&hierarchy=' + encodeURIComponent(Hierarchy);

    myCropper.setParams();
}

/* ++ Form Handling ++ */

(function() {
    var rangeForm = document.getElementById('range_form');
    if (rangeForm != null && rangeForm.length) {
        rangeForm.addEventListener('submit', function() {
            // IMPORTANT: avoid using form.action as the base URL.
            // Browsers expose it as an absolute URL even when the HTML action
            // attribute is relative/empty, which breaks linkstyle=relative.
            // Prefer the literal attribute value; if missing, treat it as empty.
            var actionAttr = rangeForm.getAttribute('action');
            var cgiurl = ((actionAttr === null) ? '' : actionAttr).split("?");

            var params = new URLSearchParams(new FormData(rangeForm));
            var qs = ['start','end','target','hierarchy','displaymode']
                .filter(function(k) { return params.has(k); })
                .map(function(k) { return k + '=' + encodeURIComponent(params.get(k)); })
                .join('&');
            rangeForm.setAttribute('action', cgiurl[0] + '?' + qs);
        });
    }
})();

/* ++ Page Init ++ */

window.addEventListener('load', function() {
    var refresh = null;
    var refreshBtn = document.getElementById('refresh-button');
    var stepMs = (window.options && window.options.step) ? window.options.step * 1000 : 300000;

    if (refreshBtn) {
        if (localStorage.getItem("noRefresh")) {
            refreshBtn.style.textDecoration = "line-through";
        } else {
            refreshBtn.style.textDecoration = "none";
            refresh = setTimeout(function() {
                location.reload();
            }, stepMs);
        }
    }

    var menuBtn = document.getElementById('menu-button');
    if (menuBtn) {
        menuBtn.addEventListener('click', function(e) {
            var body = document.getElementById('body');
            if (document.getElementById('sidebar').style.left === '0px' ||
                getComputedStyle(document.getElementById('sidebar')).left === '0px') {
                body.classList.add('sidebar-hidden');
                body.classList.remove('sidebar-visible');
            } else {
                body.classList.remove('sidebar-hidden');
                body.classList.add('sidebar-visible');
            }
            e.preventDefault();
            e.stopPropagation();
        });
    }

    if (refreshBtn) {
        refreshBtn.addEventListener('click', function(e) {
            if (localStorage.getItem("noRefresh")) {
                localStorage.removeItem("noRefresh");
                refresh = setTimeout(function() {
                    location.reload();
                }, stepMs);
                refreshBtn.style.textDecoration = "none";
            } else {
                clearTimeout(refresh);
                localStorage.setItem("noRefresh", true);
                refreshBtn.style.textDecoration = "line-through";
            }
            e.preventDefault();
            e.stopPropagation();
        });
    }

    var zoomEl = document.getElementById('zoom');
    if (zoomEl != null) {
        myCropper = initCropper(zoomEl, changeRRDImage);
    }
});
