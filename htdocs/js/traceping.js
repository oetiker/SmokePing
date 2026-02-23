/*
 * Traceping - Traceroute history panel for SmokePing
 * Loads traceroute data via AJAX when viewing a target detail page.
 */
(function() {
    'use strict';

    function getTargetFromURL() {
        var match = window.location.search.match(/target=([^&]+)/);
        return match ? match[1] : null;
    }

    function loadTraceroute(target, container) {
        var cgiurl = document.querySelector('form') ?
            (document.querySelector('form').getAttribute('action') || '') : '';
        if (!cgiurl) {
            var links = document.querySelectorAll('a[href*="smokeping"]');
            for (var i = 0; i < links.length; i++) {
                var href = links[i].getAttribute('href');
                if (href && href.indexOf('smokeping.cgi') !== -1) {
                    cgiurl = href.split('?')[0];
                    break;
                }
            }
        }
        if (!cgiurl) cgiurl = '?';

        var url = cgiurl + (cgiurl.indexOf('?') === -1 ? '?' : '&') +
            'traceping_target=' + encodeURIComponent(target);

        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    var text = xhr.responseText;
                    // Extract traceping data if embedded in page
                    var marker = '<!--TRACEPING_DATA-->';
                    var idx = text.indexOf(marker);
                    if (idx !== -1) {
                        text = text.substring(idx + marker.length);
                        var end = text.indexOf('<!--/TRACEPING_DATA-->');
                        if (end !== -1) text = text.substring(0, end);
                    }
                    container.innerHTML = '<pre style="background:#1e1e1e;color:#d4d4d4;' +
                        'padding:12px;border-radius:4px;font-size:11px;line-height:1.4;' +
                        'overflow-x:auto;max-height:400px;">' + text + '</pre>';
                } else {
                    container.innerHTML = '<p style="color:#999;font-size:12px;">Traceroute data not available.</p>';
                }
            }
        };
        xhr.send();
    }

    function init() {
        var target = getTargetFromURL();
        if (!target || target.indexOf('.') === -1) return;

        // Only show on detail pages (not overview)
        var details = document.querySelector('.details');
        if (!details) return;

        var panel = document.createElement('div');
        panel.className = 'panel';
        panel.style.marginTop = '10px';
        panel.style.width = '100%';
        panel.innerHTML = '<div class="panel-heading"><h2>Traceroute</h2></div>' +
            '<div class="panel-body" id="traceping-content">' +
            '<p style="color:#999;font-size:12px;">Loading traceroute...</p></div>';

        details.appendChild(panel);
        loadTraceroute(target, document.getElementById('traceping-content'));
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
