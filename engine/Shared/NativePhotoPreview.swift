import UIKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

/// Ephemeral local preview only. PHPicker grants access to the selected item;
/// no library-wide authorization, upload or cross-project file storage occurs.
final class NativePhotoPreview:NSObject,PHPickerViewControllerDelegate {
 private weak var host:UIViewController?
 private var completion:((String)->Void)?
 private var titleText="",messageText="",closeText=""
 func start(from host:UIViewController,title:String,message:String,close:String,completion:@escaping(String)->Void){
  self.host=host;self.completion=completion;titleText=title;messageText=message;closeText=close
  var configuration=PHPickerConfiguration();configuration.filter = .images;configuration.selectionLimit=1
  let picker=PHPickerViewController(configuration:configuration);picker.delegate=self
  host.present(picker,animated:true)
 }
 private func finish(_ status:String){let callback=completion;completion=nil;callback?(status)}
 func picker(_ picker:PHPickerViewController,didFinishPicking results:[PHPickerResult]){
  picker.dismiss(animated:true){[weak self] in
   guard let self=self else{return}
   guard let provider=results.first?.itemProvider else{self.finish("cancelled");return}
   provider.loadFileRepresentation(forTypeIdentifier:UTType.image.identifier){[weak self] url,error in
    var image:UIImage?
    if error==nil,let url=url,let source=CGImageSourceCreateWithURL(url as CFURL,nil),
       let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2400,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary){image=UIImage(cgImage:thumbnail)}
    DispatchQueue.main.async{
     guard let self=self else{return}
     guard let host=self.host,host.view.window != nil,host.presentedViewController==nil,let image=image else{self.finish("failed");return}
     let review=PhotoReviewController(image:image,title:self.titleText,message:self.messageText,close:self.closeText)
     review.onClose={[weak self] in self?.finish("selected")};review.isModalInPresentation=true
     host.present(review,animated:true)
    }
   }
  }
 }
}
private final class PhotoReviewController:UIViewController {
 private let image:UIImage,titleText:String,messageText:String,closeText:String
 var onClose:(()->Void)?
 init(image:UIImage,title:String,message:String,close:String){self.image=image;titleText=title;messageText=message;closeText=close;super.init(nibName:nil,bundle:nil);modalPresentationStyle = .formSheet}
 required init?(coder:NSCoder){fatalError("init(coder:) is unavailable")}
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .systemBackground
  let stack=UIStackView();stack.axis = .vertical;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=false
  let heading=UILabel();heading.text=titleText;heading.font = .preferredFont(forTextStyle:.headline);heading.numberOfLines=0
  let photo=UIImageView(image:image);photo.contentMode = .scaleAspectFit;photo.clipsToBounds=true;photo.accessibilityLabel=titleText
  let caption=UILabel();caption.text=messageText;caption.numberOfLines=0;caption.font = .preferredFont(forTextStyle:.body)
  let close=UIButton(type:.system);close.setTitle(closeText,for:.normal);close.addTarget(self,action:#selector(closePreview),for:.touchUpInside)
  for child in [heading,photo,caption,close]{stack.addArrangedSubview(child)};view.addSubview(stack)
  let guide=view.safeAreaLayoutGuide
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:guide.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:guide.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:guide.topAnchor,constant:24),stack.bottomAnchor.constraint(lessThanOrEqualTo:guide.bottomAnchor,constant:-24),photo.heightAnchor.constraint(equalToConstant:280),close.heightAnchor.constraint(greaterThanOrEqualToConstant:44)])
 }
 @objc private func closePreview(){dismiss(animated:true){[weak self] in self?.onClose?();self?.onClose=nil}}
}
