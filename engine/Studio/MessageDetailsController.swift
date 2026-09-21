import UIKit

/// Detail length never affects the modal or its close button's bounds.
final class MessageDetailsController:UIViewController {
 private let message:String
 init(title:String,message:String){self.message=message;super.init(nibName:nil,bundle:nil);self.title=title;modalPresentationStyle = .formSheet;preferredContentSize=CGSize(width:600,height:520)}
 required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
 override var keyCommands:[UIKeyCommand]?{[UIKeyCommand(input:UIKeyCommand.inputEscape,modifierFlags:[],action:#selector(close))]}
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .systemBackground
  let heading=UILabel();heading.text=title;heading.font = .preferredFont(forTextStyle:.headline);heading.numberOfLines=2
  let closeButton=UIButton(type:.system);closeButton.setTitle("关闭",for:.normal);closeButton.addTarget(self,action:#selector(close),for:.touchUpInside);closeButton.accessibilityIdentifier="message.close"
  let body=UITextView();body.text=message;body.font = .preferredFont(forTextStyle:.body);body.isEditable=false;body.isSelectable=true;body.alwaysBounceVertical=true;body.accessibilityIdentifier="message.details"
  for item in [heading,closeButton,body]{item.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(item)}
  let guide=view.safeAreaLayoutGuide
  NSLayoutConstraint.activate([
   heading.topAnchor.constraint(equalTo:guide.topAnchor,constant:20),heading.leadingAnchor.constraint(equalTo:guide.leadingAnchor,constant:24),heading.trailingAnchor.constraint(equalTo:closeButton.leadingAnchor,constant:-16),
   closeButton.topAnchor.constraint(equalTo:guide.topAnchor,constant:12),closeButton.trailingAnchor.constraint(equalTo:guide.trailingAnchor,constant:-20),closeButton.widthAnchor.constraint(equalToConstant:64),closeButton.heightAnchor.constraint(equalToConstant:44),
   body.topAnchor.constraint(equalTo:heading.bottomAnchor,constant:20),body.topAnchor.constraint(greaterThanOrEqualTo:closeButton.bottomAnchor,constant:8),body.leadingAnchor.constraint(equalTo:guide.leadingAnchor,constant:20),body.trailingAnchor.constraint(equalTo:guide.trailingAnchor,constant:-20),body.bottomAnchor.constraint(equalTo:guide.bottomAnchor,constant:-20)
  ])
 }
 @objc private func close(){dismiss(animated:true)}
}
