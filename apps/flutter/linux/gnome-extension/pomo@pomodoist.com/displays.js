// Mutter DisplayConfig provides stable connector identities; Shell provides geometry.
// Do not use numeric monitor indexes as persisted display IDs.
export function shellDisplays(logicals, physicals, monitors, workArea, primaryIndex) {
    const names = new Map(physicals.map(([spec, , properties]) => {
        const name = properties['display-name'];
        return [spec[0], name?.deep_unpack ? name.deep_unpack() : name];
    }));
    const displays = [];
    let primaryDisplayId = '';
    for (const monitor of monitors) {
        const logical = logicals.find(l => l[0] === monitor.x && l[1] === monitor.y);
        if (!logical || !logical[5]?.length)
            continue;
        const connectors = logical[5].map(spec => spec[0]).filter(Boolean).sort();
        if (!connectors.length)
            continue;
        const work = workArea(monitor.index);
        const id = `gnome:${connectors.join('+')}`;
        displays.push({id, name: names.get(connectors[0]) || connectors.join(' + '),
            x: monitor.x, y: monitor.y, width: monitor.width, height: monitor.height,
            workX: work.x, workY: work.y, workWidth: work.width, workHeight: work.height,
            scale: logical[2]});
        if (monitor.index === primaryIndex)
            primaryDisplayId = id;
    }
    // A partially joined topology must not be used for authoritative placement.
    if (displays.length !== monitors.length)
        return {displays: [], primaryDisplayId: ''};
    return {displays, primaryDisplayId};
}
