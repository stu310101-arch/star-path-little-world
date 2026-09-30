"""Download the two licensed asset archives in checked HTTP byte ranges."""
import urllib.request, concurrent.futures, pathlib, zipfile, time
base=pathlib.Path(__file__).resolve().parents[1]/'assets/source/urban'
sources=[('commercial','kenney-city-commercial.zip','https://kenney.nl/media/pages/assets/city-kit-commercial/a742d900eb-1753115042/kenney_city-kit-commercial_2.1.zip',4096974),('cars','kenney-cars.zip','https://kenney.nl/media/pages/assets/car-kit/1a312ec241-1775131960/kenney_car-kit.zip',4814237)]
for folder,name,url,total in sources:
    path=base/name
    prefix=path.read_bytes() if path.exists() else b''
    ranges=[(i,min(i+196607,total-1)) for i in range(len(prefix),total,196608)]
    def fetch(pair):
        a,b=pair
        for attempt in range(3):
            try:
                req=urllib.request.Request(url,headers={'Range':f'bytes={a}-{b}'})
                with urllib.request.urlopen(req,timeout=35) as response:
                    assert response.status==206
                    assert response.headers['Content-Range'].startswith(f'bytes {a}-{b}/')
                    data=response.read()
                    assert len(data)==b-a+1
                    return data
            except Exception:
                if attempt==2: raise
                time.sleep(1)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        data=prefix+b''.join(pool.map(fetch,ranges))
    assert len(data)==total
    path.write_bytes(data)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        root=(base/folder).resolve()
        for item in archive.infolist():
            assert (root/item.filename).resolve().is_relative_to(root)
        archive.extractall(root)
    print('VERIFIED',name,total,flush=True)
