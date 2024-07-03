/*
* Copyright (c) 2024 Moritz Buhl <mbuhl@moritzbuhl.de>
*
* Permission to use, copy, modify, and distribute this software for any
* purpose with or without fee is hereby granted, provided that the above
* copyright notice and this permission notice appear in all copies.
*
* THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
* WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
* MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
* ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
* WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
* ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
* OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
*/
'use strict';

function merge_rows() {
    const utilization = document.getElementsByClassName('utilization')[0];
    const otbody = utilization.children[1];
    const tbody = otbody.cloneNode(1);

    let otr = [];
    for (const trc of tbody.children) {
	const tr = trc.children;
	const len = trc.childElementCount;
	if (!otr.length) {
	    for (let i = 0; i < len; i++) {
		otr[i] = tr[i];
	    }
	    continue;
	}

	if (len != otr.length) {
	    console.warn(`inhomogeneous cell count: ${len} vs ${otr.length}.`);
	    return;
	}
	for (let i = 0; i < 6; i++) {
	    if (tr[i].innerText && otr[i].innerText == tr[i].innerText) {
		let rowspan = Number(otr[i].getAttribute('rowspan'));
		if (!rowspan) {
		    rowspan = 1;
		}
		otr[i].setAttribute('rowspan', rowspan + 1);
		tr[i].hidden = 1;
	    } else {
		tr[i].hidden = 0;
		otr[i] = tr[i];
	    }
	}
    }

    otbody.replaceWith(tbody);
}

function sort_by_col(ev) {
    const utilization = document.getElementsByClassName('utilization')[0];
    const otbody = utilization.children[1];
    const tbody = otbody.cloneNode(0);
    const thead = utilization.children[0].children[0].children;
    let col;
    let rows = [];

    for (col = 0; col < thead.length; col++) {
	if (thead[col] == ev.target) break;
    }

    for (const tr of otbody.children) {
	rows.push(tr);
    }

    rows.sort((a,b) => {
	let c = col;
	do {
	    if (c > 5)
		c = 1;
	    if (a.children[c].innerText == b.children[c].innerText) {
		c++;
	    } else
		break;
	} while (c != col);

	/* XXX: return >= depending on arrow */
	return a.children[c].innerText < b.children[c].innerText;
    });

    for (const tr of rows) {
	tbody.appendChild(tr);
    }

    tbody.innerHTML = tbody.innerHTML.replaceAll('hidden=""', '').replaceAll(
	'rowspan=', 'foo='); // XXX

    otbody.replaceWith(tbody);
    merge_rows();
}

function filter_by_target(ev) {
    const utilization = document.getElementsByClassName('utilization')[0];
    const otbody = utilization.children[1];
    const tbody = otbody.cloneNode(0);
    const par = ev.target.parentElement.children;
    let col;
    let match = [], others = [];

    for (col = 0; col < par.length; col++) {
	if (par[col] == ev.target) break;
    }

    for (const tr of otbody.children) {
	if (tr.children[col].innerText == ev.target.innerText)
	    match.push(tr);
	else
	    others.push(tr);
    }

    for (const tr of match) {
	tbody.appendChild(tr);
    }
    for (const tr of others) {
	tbody.appendChild(tr);
    }

    tbody.innerHTML = tbody.innerHTML.replaceAll('hidden=""', '').replaceAll(
	'rowspan=', 'foo='); // XXX

    otbody.replaceWith(tbody);
    merge_rows();
    const descs = utilization.children[1].getElementsByClassName('desc');
    for (let i = 0; i < descs.length; i++) {
	let td = descs[i];
	td.onclick = filter_by_target;
    }
}

window.addEventListener("load", () => {
    merge_rows();
    const utilization = document.getElementsByClassName('utilization')[0];
    const thead_tr = utilization.children[0].children[0].children;
    const descs = utilization.children[1].getElementsByClassName('desc');

    thead_tr[1].innerHTML = "IP";
    thead_tr[2].innerHTML = "Transport";
    thead_tr[3].innerHTML = "Direction";
    thead_tr[4].innerHTML = "Test";
    thead_tr[5].innerHTML = "Modifier";
    for (let i = 1; i <= 5; i++) {
	thead_tr[i].innerHTML += " &rarr;";
	thead_tr[i].classList.add("desc");
	/* XXX: add on-click listeners for td.descs */
	thead_tr[i].addEventListener("click", sort_by_col);
    }
    for (let i = 0; i < descs.length; i++) {
	let td = descs[i];
	td.onclick = filter_by_target;
    }
});
