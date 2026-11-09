import math
import turtle

class Spiro:
    # 构造函数
    def __init__(self, xc, yc, col, R, r, l):

        # 创建turtle对象
        self.t = turtle.Turtle()
        # 设置光标形状
        self.t.shape("turtle")
        # 设置以度为单位的步长
        self.step = 5
        # 设置绘画结束标志
        self.drawingComplete = False

        # 设置参数
        self.setparams(xc, yc, col, R, r, l)

        # 开始绘画
        self.restart()

    def setparams(self,xc, yc, col, R, r, l):
        # 设置定义繁花曲线的参数
        self.xc = xc
        self.yc = yc
        self.R = int(R)
        self.r = int(r)
        self.l = l
        self.col = col
        # 通过除以GCD将分数约分
        gcdVal = math.gcd(self.r,self.R)
        self.nRot = self.r/gcdVal
        # 计算半径比
        self.k = r/float(R)
        # 设置颜色
        self.t.color(*col)
        #存储当前角度
        self.a = 0

    def restart(self):
        # 设置绘画结束标志
        self.drawingComplete = False
        #显示海龟
        self.t.showturtle()
        # 移到起始位置
        self.t.up()
        R, k, l = self.R, self.k, self.l
        a = 0.0
        x = R*((1-k)*math.cos(a) + 1*k*math.cos((1-k)*a/k))
        y = R*((1-k)*math.sin(a) + 1*k*math.sin((1-k)*a/k))
        self.t.setpos(self.xc + x, self.yc + y)
        self.t.down()

    def draw(self):
        # 绘制余下的线段
        R, k, l = self.R, self.k, self.l
        for i in range(0, 360*self.nRot + 1, self.step):
            a = math.radians(i)
            x = R*((1-k)*math.cos(a) + 1*k*math.cos((1-k)*a/k))
            y = R*((1-k)*math.sin(a) + 1*k*math.sin((1-k)*a/k))

            try:
                self.t.setpos(self.xc + x, self.yc + y)
            except:
                print("Exception,exiting.")
                exit(0)
        # 繁花曲线已绘制完毕，因此隐藏海龟光标
        self.t.hideturtle()

    def update(self):
        # 如果繁花曲线已绘制完毕，就跳过后面的步骤
        if self.drawingComplete:
            return
        # 递增角度
        self.a += self.step
        # 绘制一条线段
        R, k, l = self.R, self.k, self.l
        # 设置角度
        a = math.radians(self.a)
        x = self.R*((1-k)*math.cos(a) + 1*k*math.cos((1-k)*a/k))
        y = self.R*((1-k)*math.sin(a) + 1*k*math.sin((1-k)*a/k))

        try:
            self.t.setpos(self.xc + x, self.yc + y)
        except:
            print("Exception,exiting.")
            exit(0)
        # 如果繁花曲线已绘制完毕，就设置相应的标志
        if self.a >= 360*self.nRot:
            self.drawingComplete = True
            # 繁花曲线已绘制完毕，因此隐藏海龟光标
            self.t.hideturtle()