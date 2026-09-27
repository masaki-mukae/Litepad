program SyntaxTest;
{ 波括弧のブロックコメント }
(* もう一つの
   ブロックコメント *)
var
  name: string;
  count: integer;
begin
  name := 'SakuraMac';
  count := 42;
  if count > 10 then
    writeln('Hello, ', name);
end.
