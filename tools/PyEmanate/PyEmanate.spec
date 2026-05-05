# -*- mode: python -*-

import pathlib
import os

#ThisFileDirectory = str(pathlib.Path('.').parent.absolute())
ThisFileDirectory = '.'

block_cipher = None

a = Analysis(
	['python/PyEmanate.py'],
	pathex=[ThisFileDirectory],
	binaries=[],
	datas=[],
	hiddenimports=[],
	hookspath=[],
	runtime_hooks=[],
	excludes=[],
	win_no_prefer_redirects=False,
	win_private_assemblies=False,
	cipher=block_cipher
)

dirname = 'qt'
for f in [fi for fi in os.listdir(os.path.join(ThisFileDirectory, dirname)) if os.path.isfile(os.path.join(ThisFileDirectory, fi))]:
	_, ext = os.path.splitext(f)
	if ext.lower() in ['.ui', '.png']:
		a.datas += [(f, './' + dirname + '/' + f, "DATA")]

dirname = 'config'
for f in [fi for fi in os.listdir(os.path.join(ThisFileDirectory, dirname)) if os.path.isfile(os.path.join(ThisFileDirectory, fi))]:
	_, ext = os.path.splitext(f)
	if ext.lower() in ['.json']:
		a.datas += [(f, './' + dirname + '/' + f, "DATA")]
	
a.datas += [('pgf.mplstyle', './python/pgf.mplstyle', "DATA")]

#a.datas += [('image.png','path_to_image', "DATA")]

pyz = PYZ(
	a.pure,
	a.zipped_data,
	cipher=block_cipher
)

exe = EXE(
	pyz,
	a.scripts,
	a.binaries,
	a.zipfiles,
	a.datas,
	name='PyEmanate',
	debug=False,
	strip=False,
	upx=True,
	console=True
)