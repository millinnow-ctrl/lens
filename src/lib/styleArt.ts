/**
 * Signature artwork per camera look. Style cards show these — the user's
 * own photo is only ever developed through a camera when they choose it,
 * one at a time. (No silent batch-rendering of all 18.)
 */
import artDisposable from '../assets/style-disposable.jpg'
import artIphoneFlash from '../assets/style-iphone-flash.jpg'
import artCamcorder from '../assets/style-camcorder-90s.jpg'
import artLeica from '../assets/style-leica-street.jpg'
import artGq from '../assets/style-gq-editorial.jpg'
import artA24 from '../assets/style-a24-still.jpg'
import artNoir from '../assets/style-film-noir.jpg'
import artY2k from '../assets/style-y2k-digicam.jpg'
import artPolaroid from '../assets/style-polaroid.jpg'
import artSuper8 from '../assets/style-super-8.jpg'
import artLomo from '../assets/style-lomo.jpg'
import artKodachrome from '../assets/style-kodachrome.jpg'
import artSecurityCam from '../assets/style-security-cam.jpg'
import artPointShoot from '../assets/style-point-shoot.jpg'
import artPastel from '../assets/style-pastel-cinema.jpg'
import artTokyoNeon from '../assets/style-tokyo-neon.jpg'
import artPhotobooth from '../assets/style-photobooth.jpg'
import artTintype from '../assets/style-tintype.jpg'

export const STYLE_ART: Record<string, string> = {
  // LM-1 wears the Leica art until its own Higgsfield card is generated
  'pro-body': artLeica,
  disposable: artDisposable,
  'iphone-flash': artIphoneFlash,
  'camcorder-90s': artCamcorder,
  'leica-street': artLeica,
  'gq-editorial': artGq,
  'a24-still': artA24,
  'film-noir': artNoir,
  'y2k-digicam': artY2k,
  polaroid: artPolaroid,
  'super-8': artSuper8,
  lomo: artLomo,
  kodachrome: artKodachrome,
  'security-cam': artSecurityCam,
  'point-shoot': artPointShoot,
  'pastel-cinema': artPastel,
  'tokyo-neon': artTokyoNeon,
  photobooth: artPhotobooth,
  tintype: artTintype,
}
